import { ApiError, apiFetch, type Media, mediaSchema } from "@flux/shared";
import { type QueryClient, useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState } from "react";

// Извлечение аудиодорожки: POST отдаёт либо готовый трек (200, уже
// извлекали), либо задание (202 {job_id}). Дальше опрашиваем статус с
// фиксированным интервалом; три сетевых сбоя подряд считаем обрывом.
export const EXTRACT_POLL_INTERVAL_MS = 1500;
export const MAX_EXTRACT_POLL_FAILURES = 3;

// Схемы задания нет в shared (там mediaSchema): контракт узкий, поэтому
// валидируем поля вручную, без зависимости mobile от zod напрямую.
export interface ExtractJobStatus {
	readonly id: number;
	readonly status: string;
	readonly error: string | null;
	readonly media: Media | null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function parseJobId(value: unknown): number {
	if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
		throw new Error("Invalid extract job id");
	}
	return value;
}

export type ExtractStartResult =
	| { kind: "track"; track: Media; alreadyExtracted: true }
	| { kind: "job"; jobId: number; alreadyExtracted: false };

export type ExtractFailureKind =
	| "conflict"
	| "unavailable"
	| "rateLimited"
	| "failed";

export interface ExtractFailure {
	readonly kind: ExtractFailureKind;
	readonly message: string;
}

export type ExtractPhase = "starting" | "queued" | "processing";

export interface ExtractResult {
	readonly track: Media;
	readonly alreadyExtracted: boolean;
}

// 200 с телом Media означает, что дорожка уже существует: второго задания
// и ffmpeg-прогона не будет. 202 — только job_id.
export function classifyExtractStart(body: unknown): ExtractStartResult {
	if (isRecord(body) && "job_id" in body) {
		return {
			kind: "job",
			jobId: parseJobId(body.job_id),
			alreadyExtracted: false,
		};
	}
	return {
		kind: "track",
		track: mediaSchema.parse(body),
		alreadyExtracted: true,
	};
}

// 200 с готовым треком означает, что извлечения больше нет: фаза должна
// сброситься, иначе isExtracting залипнет навсегда. 202 — задание сразу
// уходит в очередь.
export function phaseAfterStart(
	kind: ExtractStartResult["kind"],
): ExtractPhase | null {
	return kind === "track" ? null : "queued";
}

export function classifyExtractStatus(body: unknown): ExtractJobStatus {
	if (!isRecord(body) || typeof body.id !== "number") {
		throw new Error("Invalid extract status");
	}
	if (typeof body.status !== "string") {
		throw new Error("Invalid extract status");
	}
	return {
		id: body.id,
		status: body.status,
		error: typeof body.error === "string" ? body.error : null,
		media:
			body.media === null || body.media === undefined
				? null
				: mediaSchema.parse(body.media),
	};
}

export function isExtractDone(status: ExtractJobStatus): boolean {
	return status.status === "done";
}

export function isExtractFailed(status: ExtractJobStatus): boolean {
	return status.status === "error";
}

// Счётчик подряд идущих сетевых сбоев опроса. Сбрасывается на любом
// успешном ответе (даже с queued/processing), поэтому «3 подряд» — именно
// серия, а не накопленные за всё время.
export function nextPollFailure(failures: number): {
	failures: number;
	giveUp: boolean;
} {
	const next = failures + 1;
	return { failures: next, giveUp: next >= MAX_EXTRACT_POLL_FAILURES };
}

// 409 — дорожка уже есть/задание готово; 503 — нет ffmpeg; 429 — общий
// rate limit (он же отдаётся при переполненной очереди). Всё остальное
// (сеть, 5xx, битый ответ) — общий сбой.
export function classifyExtractError(error: unknown): ExtractFailure {
	if (error instanceof ApiError) {
		if (error.status === 409) {
			return { kind: "conflict", message: error.message };
		}
		if (error.status === 503) {
			return { kind: "unavailable", message: error.message };
		}
		if (error.status === 429) {
			return { kind: "rateLimited", message: error.message };
		}
		return { kind: "failed", message: error.message };
	}
	return {
		kind: "failed",
		message: error instanceof Error ? error.message : "",
	};
}

interface CancellableDelay {
	wait: (ms: number) => Promise<void>;
	cancel: () => void;
}

// Задержка между опросами, которую можно снять при unmount/отмене:
// обычный setTimeout после ухода с экрана остался бы висеть до тика.
export function createCancellableDelay(): CancellableDelay {
	let timer: ReturnType<typeof setTimeout> | null = null;
	let resolveWait: (() => void) | null = null;

	const clear = () => {
		if (timer !== null) {
			clearTimeout(timer);
			timer = null;
		}
		if (resolveWait !== null) {
			const resolve = resolveWait;
			resolveWait = null;
			resolve();
		}
	};

	return {
		wait: (ms) =>
			new Promise<void>((resolve) => {
				resolveWait = resolve;
				timer = setTimeout(() => {
					timer = null;
					resolveWait = null;
					resolve();
				}, ms);
			}),
		cancel: clear,
	};
}

interface ExtractRun {
	jobId: number | null;
	cancelled: boolean;
	// true только для ручной отмены: unmount не должен удалять задание на
	// сервере, иначе поздний DELETE убьёт новый прогон, который мог
	// подхватить то же активное задание.
	explicitCancel: boolean;
	readonly controller: AbortController;
}

function invalidateMediaLists(queryClient: QueryClient): void {
	// Только media: новый трек должен появиться в аудио-разделе, а
	// избранное/коллекции извлечение не меняет.
	void queryClient.invalidateQueries({ queryKey: ["media"] });
}

async function cancelExtractJob(jobId: number): Promise<void> {
	await apiFetch<unknown>(`/media/extract/${jobId}`, { method: "DELETE" });
}

type ExtractPollOutcome =
	| { kind: "done"; result: ExtractResult }
	| { kind: "failed"; failure: ExtractFailure }
	| { kind: "cancelled" };

export interface ExtractPollOptions {
	readonly jobId: number;
	readonly signal: AbortSignal;
	readonly isActive: () => boolean;
	readonly wait: () => Promise<void>;
	readonly onPhase: (phase: ExtractPhase) => void;
	// Точка подмены для тестов; в приложении — apiFetch статуса.
	readonly fetchStatus?: (
		jobId: number,
		signal: AbortSignal,
	) => Promise<unknown>;
}

async function fetchExtractStatus(
	jobId: number,
	signal: AbortSignal,
): Promise<unknown> {
	return await apiFetch<unknown>(`/media/extract/${jobId}`, { signal });
}

// Цикл опроса вынесен из хука: start остаётся коротким, а вся политика
// «3 сбоя подряд / done / error» живёт в одной функции. Экспортирован для
// тестов без RNTL: wait/isActive/fetchStatus подменяются.
export async function pollExtractJob({
	jobId,
	signal,
	isActive,
	wait,
	onPhase,
	fetchStatus = fetchExtractStatus,
}: ExtractPollOptions): Promise<ExtractPollOutcome> {
	let failures = 0;
	while (isActive()) {
		await wait();
		if (!isActive()) {
			return { kind: "cancelled" };
		}

		let job: ExtractJobStatus;
		try {
			const raw = await fetchStatus(jobId, signal);
			job = classifyExtractStatus(raw);
		} catch (error) {
			if (!isActive()) {
				return { kind: "cancelled" };
			}
			const next = nextPollFailure(failures);
			failures = next.failures;
			if (next.giveUp) {
				return { kind: "failed", failure: classifyExtractError(error) };
			}
			continue;
		}

		failures = 0;
		if (isExtractDone(job)) {
			const track = job.media ?? null;
			if (track === null) {
				return {
					kind: "failed",
					failure: { kind: "failed", message: job.error ?? "" },
				};
			}
			return {
				kind: "done",
				result: { track, alreadyExtracted: false },
			};
		}
		if (isExtractFailed(job)) {
			return {
				kind: "failed",
				failure: { kind: "failed", message: job.error ?? "" },
			};
		}
		// queued/processing: показываем актуальную фазу, а не «извлечение»
		// с первого кадра.
		onPhase(job.status === "processing" ? "processing" : "queued");
	}
	return { kind: "cancelled" };
}

export interface ExtractAudioState {
	readonly isExtracting: boolean;
	readonly phase: ExtractPhase | null;
	readonly failure: ExtractFailure | null;
	readonly start: () => Promise<ExtractResult | null>;
	readonly cancel: () => Promise<void>;
}

// Хук держит один активный прогон: повторный старт во время извлечения
// игнорируется (кнопка и так disabled). Unmount только снимает опрос
// (как web), а DELETE шлёт лишь ручная отмена.
export function useExtractAudio(mediaId: number): ExtractAudioState {
	const queryClient = useQueryClient();
	const [phase, setPhase] = useState<ExtractPhase | null>(null);
	const [failure, setFailure] = useState<ExtractFailure | null>(null);
	const runRef = useRef<ExtractRun | null>(null);
	const delayRef = useRef<CancellableDelay | null>(null);

	const getDelay = useCallback((): CancellableDelay => {
		if (delayRef.current === null) {
			delayRef.current = createCancellableDelay();
		}
		return delayRef.current;
	}, []);

	const stop = useCallback((run: ExtractRun) => {
		run.cancelled = true;
		run.controller.abort();
		delayRef.current?.cancel();
		if (runRef.current === run) {
			runRef.current = null;
		}
	}, []);

	// Единая точка завершения: снять прогон и убрать isExtracting. Нужна
	// и для 200-трека, где опроса не было вовсе.
	const finish = useCallback(
		(run: ExtractRun) => {
			stop(run);
			setPhase(null);
		},
		[stop],
	);

	// Unmount: только гасим опрос/запросы статуса. Задание на сервере
	// продолжает жить: DELETE здесь гонялся бы с новым прогоном, который
	// после перемонтирования мог подхватить то же активное задание.
	useEffect(
		() => () => {
			const run = runRef.current;
			if (run !== null) {
				stop(run);
			}
		},
		[stop],
	);

	const start = useCallback(async (): Promise<ExtractResult | null> => {
		if (runRef.current !== null) {
			return null;
		}
		const run: ExtractRun = {
			jobId: null,
			cancelled: false,
			explicitCancel: false,
			controller: new AbortController(),
		};
		runRef.current = run;
		setFailure(null);
		setPhase("starting");

		try {
			let parsedStart: ExtractStartResult;
			try {
				const body = await apiFetch<unknown>(`/media/${mediaId}/extract`, {
					method: "POST",
				});
				parsedStart = classifyExtractStart(body);
			} catch (error) {
				if (runRef.current === run) {
					setFailure(classifyExtractError(error));
					setPhase(null);
					runRef.current = null;
				}
				return null;
			}

			// Ручная отмена/unmount случились, пока POST был в полёте. Для
			// явной отмены id задания узнали только сейчас — удаляем; при
			// unmount задание оставляем серверу (см. cleanup выше).
			if (run.cancelled || runRef.current !== run) {
				if (run.explicitCancel && parsedStart.kind === "job") {
					void cancelExtractJob(parsedStart.jobId).catch(() => {
						// Задание уже завершилось — отменять нечего.
					});
				}
				return null;
			}

			// 200-трек: фазы извлечения нет — finish сбросит её ниже.
			// 202: задание сразу в очереди.
			setPhase(phaseAfterStart(parsedStart.kind));
			if (parsedStart.kind === "track") {
				finish(run);
				invalidateMediaLists(queryClient);
				return {
					track: parsedStart.track,
					alreadyExtracted: true,
				};
			}

			run.jobId = parsedStart.jobId;
			const outcome = await pollExtractJob({
				jobId: run.jobId,
				signal: run.controller.signal,
				isActive: () => runRef.current === run && !run.cancelled,
				wait: () => getDelay().wait(EXTRACT_POLL_INTERVAL_MS),
				onPhase: setPhase,
			});
			if (outcome.kind === "cancelled") {
				return null;
			}
			finish(run);
			if (outcome.kind === "failed") {
				setFailure(outcome.failure);
				return null;
			}
			invalidateMediaLists(queryClient);
			return outcome.result;
		} finally {
			if (runRef.current === run) {
				runRef.current = null;
			}
		}
	}, [finish, getDelay, mediaId, queryClient]);

	const cancel = useCallback(async (): Promise<void> => {
		const run = runRef.current;
		if (run === null) {
			return;
		}
		const jobId = run.jobId;
		run.explicitCancel = true;
		stop(run);
		setPhase(null);
		setFailure(null);
		if (jobId === null) {
			return;
		}
		try {
			await cancelExtractJob(jobId);
		} catch {
			// 404/409: задание уже исчезло или готово — итог тот же.
		}
	}, [stop]);

	return {
		isExtracting: phase !== null,
		phase,
		failure,
		start,
		cancel,
	};
}

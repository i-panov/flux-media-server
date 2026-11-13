import { useQueryClient } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState } from "react";
import {
	cancelUploadJob,
	classifyUploadError,
	fetchUploadJob,
	startUpload,
	UPLOAD_POLL_INTERVAL_MS,
	UploadAbortedError,
	type UploadDuplicate,
	type UploadJobRef,
	type UploadSource,
} from "../api/upload";
import { t } from "../i18n";
import {
	createUploadSemaphore,
	isActiveUploadStatus,
	MAX_PARALLEL_UPLOADS,
	type UploadItemStatus,
	type UploadSemaphore,
} from "./queue";

export interface UploadQueueItem {
	readonly key: string;
	readonly source: UploadSource;
	readonly status: UploadItemStatus;
	readonly progress: number | null;
	readonly error: string;
	readonly duplicate: UploadDuplicate | null;
	readonly job: UploadJobRef | null;
	readonly mediaTitle: string;
}

export interface UploadCompleted {
	readonly key: string;
	readonly title: string;
}

type ProcessItem = (key: string, force: boolean) => void;

interface PipelineContext {
	readonly force: boolean;
	readonly source: UploadSource;
	readonly semaphore: UploadSemaphore;
	readonly isCurrent: () => boolean;
	readonly patch: (patch: Partial<UploadQueueItem>) => void;
	readonly registerAbort: (abort: () => void) => void;
	readonly clearAbort: () => void;
	readonly invalidate: () => void;
	readonly onDone: (title: string) => void;
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => {
		setTimeout(resolve, ms);
	});
}

function errorMessage(error: unknown): string {
	switch (classifyUploadError(error)) {
		case "timeout":
			return t("upload.timeout");
		case "tooLarge":
			return t("upload.tooLarge");
		case "rateLimited":
			return t("upload.tooMany");
		case "network":
			return t("upload.networkError");
		default:
			return error instanceof Error ? error.message : "";
	}
}

// POST под семафором, затем независимый поллинг серверной обработки.
// Слот освобождается сразу после enqueue: зависший transcode не должен
// блокировать загрузку следующих файлов.
async function pollUploadJob(
	ctx: PipelineContext,
	job: UploadJobRef | null,
): Promise<void> {
	while (job !== null) {
		if (!ctx.isCurrent()) {
			return;
		}
		const status = await fetchUploadJob(job);
		if (!ctx.isCurrent()) {
			return;
		}
		if (status.status === "done") {
			const title = status.media?.title ?? ctx.source.name;
			ctx.patch({
				status: "done",
				progress: 100,
				mediaTitle: title,
				error: "",
				duplicate: null,
				job: null,
			});
			ctx.invalidate();
			ctx.onDone(title);
			return;
		}
		if (status.status === "duplicate") {
			ctx.patch({
				status: "error",
				progress: null,
				error: status.error ?? "",
				duplicate: status.duplicate,
				job: null,
			});
			return;
		}
		if (status.status === "error" || status.status === "cancelled") {
			ctx.patch({
				status: status.status,
				progress: null,
				error: status.error ?? "",
				job: null,
			});
			return;
		}
		ctx.patch({ status: "processing", progress: status.progress });
		await sleep(UPLOAD_POLL_INTERVAL_MS);
	}
}

async function runUploadPipeline(ctx: PipelineContext): Promise<void> {
	const release = await ctx.semaphore.acquire();
	let job: UploadJobRef | null = null;
	try {
		if (!ctx.isCurrent()) {
			return;
		}
		ctx.patch({ status: "uploading", progress: 0 });
		const task = startUpload(ctx.source, {
			force: ctx.force,
			onProgress: (progress) => {
				if (ctx.isCurrent()) {
					ctx.patch({ progress });
				}
			},
		});
		ctx.registerAbort(task.abort);
		try {
			job = await task.promise;
		} finally {
			ctx.clearAbort();
		}
		if (!ctx.isCurrent()) {
			// Отменили, пока POST летел: задание на сервере всё же создано —
			// гасим его, иначе файл обработается впустую.
			if (job !== null) {
				void cancelUploadJob(job).catch(() => undefined);
			}
			return;
		}
		ctx.patch({
			status: "processing",
			job,
			// У upload-заданий прогресса нет; у транскода он появится после
			// первого опроса.
			progress: job.kind === "transcode" ? 0 : 100,
		});
	} finally {
		release();
	}
	await pollUploadJob(ctx, job);
}

// Очередь загрузок: каждый файл независим, ответы устаревших попыток
// отсекаются тикетом (отмена/повтор/force). Максимум два POST одновременно.
// Уход с экрана отменяет активные загрузки: без фоновой задачи продолжать
// их после размонтирования нечем, а серверные задания отменяются явно.
// Системных уведомлений нет: lastCompleted — in-app баннер, который виден
// только на открытом экране и не догоняет пользователя после ухода.
/* eslint-disable max-lines-per-function -- очередь держит XHR, поллинг и отмену. */
export function useUploadQueue() {
	const queryClient = useQueryClient();
	const [items, setItems] = useState<UploadQueueItem[]>([]);
	const [completed, setCompleted] = useState<UploadCompleted | null>(null);
	const itemsRef = useRef<UploadQueueItem[]>([]);
	const cancelOnLeave = useRef<ReturnType<typeof setTimeout> | null>(null);
	const counter = useRef(0);
	const tokens = useRef(new Map<string, number>());
	const cancelled = useRef(new Set<string>());
	const active = useRef(new Set<string>());
	const pendingRetry = useRef(new Map<string, boolean>());
	const processItemRef = useRef<ProcessItem | null>(null);
	const aborts = useRef(new Map<string, () => void>());
	const stopped = useRef(false);
	const semaphoreRef = useRef<UploadSemaphore | null>(null);
	if (semaphoreRef.current === null) {
		semaphoreRef.current = createUploadSemaphore(MAX_PARALLEL_UPLOADS);
	}

	const patchItem = useCallback(
		(key: string, patch: Partial<UploadQueueItem>) => {
			itemsRef.current = itemsRef.current.map((item) =>
				item.key === key ? { ...item, ...patch } : item,
			);
			setItems(itemsRef.current);
		},
		[],
	);

	const bumpToken = useCallback((key: string): number => {
		const next = (tokens.current.get(key) ?? 0) + 1;
		tokens.current.set(key, next);
		return next;
	}, []);

	const isCurrent = useCallback(
		(key: string, token: number) => tokens.current.get(key) === token,
		[],
	);

	const invalidateAfterUpload = useCallback(() => {
		void queryClient.invalidateQueries({ queryKey: ["media"] });
		void queryClient.invalidateQueries({ queryKey: ["collections"] });
		void queryClient.invalidateQueries({ queryKey: ["artists"] });
	}, [queryClient]);

	const processItem = useCallback(
		async (key: string, force: boolean): Promise<void> => {
			if (
				stopped.current ||
				cancelled.current.has(key) ||
				active.current.has(key)
			) {
				return;
			}
			const item = itemsRef.current.find((row) => row.key === key);
			const semaphore = semaphoreRef.current;
			if (item === undefined || semaphore === null) {
				return;
			}
			active.current.add(key);
			const token = bumpToken(key);
			patchItem(key, {
				status: "queued",
				progress: null,
				error: "",
				duplicate: null,
				job: null,
				mediaTitle: "",
			});
			try {
				await runUploadPipeline({
					force,
					source: item.source,
					semaphore,
					isCurrent: () => isCurrent(key, token),
					patch: (patch) => {
						if (isCurrent(key, token)) {
							patchItem(key, patch);
						}
					},
					registerAbort: (abort) => aborts.current.set(key, abort),
					clearAbort: () => aborts.current.delete(key),
					invalidate: invalidateAfterUpload,
					onDone: (title) => setCompleted({ key, title }),
				});
			} catch (error) {
				if (!isCurrent(key, token)) {
					return;
				}
				if (error instanceof UploadAbortedError) {
					patchItem(key, { status: "cancelled", progress: null });
					return;
				}
				// Поллинг упал: не оставляем серверное задание жить рядом
				// с кнопкой retry, иначе повтор создаст второй job.
				const failedJob = itemsRef.current.find((row) => row.key === key)?.job;
				if (failedJob !== null && failedJob !== undefined) {
					void cancelUploadJob(failedJob).catch(() => undefined);
				}
				patchItem(key, {
					status: "error",
					progress: null,
					error: errorMessage(error),
					job: null,
				});
			} finally {
				active.current.delete(key);
				const retryForce = pendingRetry.current.get(key);
				if (retryForce !== undefined) {
					pendingRetry.current.delete(key);
					processItemRef.current?.(key, retryForce);
				}
			}
		},
		[bumpToken, invalidateAfterUpload, isCurrent, patchItem],
	);

	useEffect(() => {
		processItemRef.current = (key, force) => {
			void processItem(key, force);
		};
	}, [processItem]);

	// Unmount/StrictMode: первый cleanup помечает очередь остановленной,
	// второй setup (StrictMode) возвращает её в работу.
	useEffect(() => {
		stopped.current = false;
		if (cancelOnLeave.current !== null) {
			clearTimeout(cancelOnLeave.current);
			cancelOnLeave.current = null;
		}
		const abortHandles = aborts.current;
		const tokenMap = tokens.current;
		return () => {
			stopped.current = true;
			for (const abort of abortHandles.values()) {
				abort();
			}
			abortHandles.clear();
			for (const key of tokenMap.keys()) {
				tokenMap.set(key, (tokenMap.get(key) ?? 0) + 1);
			}
			// StrictMode сразу перезапустит effect и отменит таймер; при
			// реальном уходе с экрана серверные processing-задания отменяем.
			cancelOnLeave.current = setTimeout(() => {
				if (!stopped.current) return;
				for (const item of itemsRef.current) {
					if (item.job !== null) {
						void cancelUploadJob(item.job).catch(() => undefined);
					}
				}
			}, 300);
		};
	}, []);

	const addFiles = useCallback(
		(sources: UploadSource[]) => {
			if (stopped.current || sources.length === 0) {
				return;
			}
			setCompleted(null);
			const created = sources.map((source) => {
				counter.current += 1;
				return {
					key: `${counter.current}-${source.name}`,
					source,
					status: "queued" as const,
					progress: null,
					error: "",
					duplicate: null,
					job: null,
					mediaTitle: "",
				};
			});
			itemsRef.current = [...created, ...itemsRef.current];
			setItems(itemsRef.current);
			for (const item of created) {
				void processItem(item.key, false);
			}
		},
		[processItem],
	);

	const cancelItem = useCallback(
		(key: string) => {
			const item = itemsRef.current.find((row) => row.key === key);
			if (item === undefined || !isActiveUploadStatus(item.status)) {
				return;
			}
			cancelled.current.add(key);
			bumpToken(key);
			aborts.current.get(key)?.();
			aborts.current.delete(key);
			if (item.job !== null) {
				void cancelUploadJob(item.job).catch(() => undefined);
			}
			patchItem(key, { status: "cancelled", progress: null });
		},
		[bumpToken, patchItem],
	);

	const retryItem = useCallback(
		(key: string, force = false) => {
			const item = itemsRef.current.find((row) => row.key === key);
			if (
				item === undefined ||
				item.status === "done" ||
				isActiveUploadStatus(item.status)
			) {
				return;
			}
			cancelled.current.delete(key);
			setCompleted(null);
			if (active.current.has(key)) {
				// Отмена во время поллинга: старый прогон ещё завершается.
				// Повтор стартует сразу после его finally, не теряясь.
				pendingRetry.current.set(key, force);
				return;
			}
			void processItem(key, force);
		},
		[processItem],
	);

	const busy = items.some((item) => isActiveUploadStatus(item.status));

	return {
		items,
		addFiles,
		cancelItem,
		retryItem,
		forceRetryItem: (key: string) => retryItem(key, true),
		busy,
		lastCompleted: completed,
		dismissCompleted: () => setCompleted(null),
	};
}

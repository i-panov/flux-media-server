import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError, apiFetch } from "../../api/client";
import {
	cancelUploadJob,
	enqueueUpload,
	fetchUploadJob,
	type UploadType,
} from "../../api/upload";
import { createUploadSemaphore, type UploadSemaphore } from "./uploadSemaphore";

const POLL_INTERVAL_MS = 900;
// Сервер буферизует тело загрузки целиком в RAM: десятки параллельных
// файлов могут положить инстанс. Слот держится только на время POST.
const MAX_PARALLEL_UPLOADS = 2;

export type ItemStatus =
	| "queued"
	| "uploading"
	| "processing"
	| "done"
	| "error"
	| "duplicate"
	| "cancelled";

export interface QueueItem {
	key: string;
	file: File;
	type: UploadType;
	status: ItemStatus;
	progress: number | null;
	error: string;
	duplicate: { id: number; title: string } | null;
	job: { id: number; kind: "upload" | "transcode" } | null;
	// Не удалось положить готовый файл в выбранную коллекцию
	// (сам файл загружен): текст ошибки для строки элемента.
	collectionError: string;
}

interface PipelineContext {
	item: QueueItem;
	force: boolean;
	token: number;
	gate: UploadSemaphore;
	shouldAbort: () => boolean;
	isCurrent: () => boolean;
	update: (patch: Partial<QueueItem>) => void;
	invalidateList: (type: UploadType) => void;
	addToCollection: (mediaId: number) => Promise<string>;
}

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => {
		setTimeout(resolve, ms);
	});
}

// POST под семафором, затем независимый поллинг серверной обработки.
// Слот освобождается сразу после enqueue: зависший transcode не стопит
// загрузку следующих файлов.
async function runUploadPipeline(ctx: PipelineContext): Promise<void> {
	let job: QueueItem["job"] = null;
	await ctx.gate.acquire();
	try {
		if (ctx.shouldAbort()) {
			return;
		}
		ctx.update({ status: "uploading" });
		const enqueued = await enqueueUpload(
			ctx.item.file,
			ctx.item.type,
			ctx.force,
		);
		if (ctx.shouldAbort()) {
			// Отменили, пока запрос летел: задание на сервере всё же
			// создано — гасим его.
			void cancelUploadJob(enqueued.jobType, enqueued.jobId).catch(
				() => undefined,
			);
			return;
		}
		job = { id: enqueued.jobId, kind: enqueued.jobType };
		ctx.update({ status: "processing", job });
	} finally {
		ctx.gate.release();
	}

	while (job !== null) {
		const status = await fetchUploadJob(job.kind, job.id);
		if (!ctx.isCurrent()) {
			return;
		}
		const progress =
			typeof status.progress === "number" ? status.progress : null;
		if (status.status === "done") {
			const mediaId = status.media?.id ?? null;
			const collectionError =
				mediaId === null ? "" : await ctx.addToCollection(mediaId);
			ctx.update({ status: "done", progress: 100, collectionError });
			ctx.invalidateList(ctx.item.type);
			return;
		}
		if (status.status === "duplicate") {
			ctx.update({
				status: "duplicate",
				progress: null,
				duplicate: status.duplicate ?? null,
			});
			return;
		}
		if (status.status === "error" || status.status === "cancelled") {
			ctx.update({
				status: status.status === "cancelled" ? "cancelled" : "error",
				progress: null,
				error: status.error ?? "",
			});
			return;
		}
		ctx.update({ status: "processing", progress });
		await sleep(POLL_INTERVAL_MS);
	}
}

// Очередь загрузок: каждый файл независим, ответы устаревших попыток
// отсекаются тикетом (отмена/повтор/force).
// targetCollectionId — коллекция экрана: готовый файл кладётся в неё
// сразу, выбор читается на старте обработки.
export function useUploadQueue(
	type: UploadType,
	targetCollectionId: number | null,
) {
	const queryClient = useQueryClient();
	const { t } = useTranslation();
	const [items, setItems] = useState<QueueItem[]>([]);
	const counter = useRef(0);
	const tokens = useRef(new Map<string, number>());
	const cancelledKeys = useRef(new Set<string>());
	const activeKeys = useRef(new Set<string>());
	const stopped = useRef(false);
	const semaphore = useRef<UploadSemaphore | null>(null);
	if (semaphore.current === null) {
		semaphore.current = createUploadSemaphore(MAX_PARALLEL_UPLOADS);
	}

	const updateItem = (key: string, patch: Partial<QueueItem>) => {
		setItems((prev) =>
			prev.map((item) => (item.key === key ? { ...item, ...patch } : item)),
		);
	};

	const bumpToken = (key: string): number => {
		const next = (tokens.current.get(key) ?? 0) + 1;
		tokens.current.set(key, next);
		return next;
	};

	const isCurrent = (key: string, token: number) =>
		tokens.current.get(key) === token;

	const invalidateList = (uploadType: UploadType) => {
		void queryClient.invalidateQueries({ queryKey: ["media", uploadType] });
	};

	const addToCollection = async (mediaId: number): Promise<string> => {
		if (targetCollectionId === null) {
			return "";
		}
		try {
			await apiFetch<unknown>(`/collections/${targetCollectionId}/items`, {
				method: "POST",
				body: JSON.stringify({ media_id: mediaId }),
			});
			void queryClient.invalidateQueries({
				queryKey: ["collections", targetCollectionId, "items"],
			});
			return "";
		} catch (error) {
			return error instanceof ApiError && error.message !== ""
				? error.message
				: t("upload.collectionErrorFallback");
		}
	};

	const processItem = async (item: QueueItem, force: boolean) => {
		if (
			stopped.current ||
			cancelledKeys.current.has(item.key) ||
			activeKeys.current.has(item.key)
		) {
			return;
		}
		activeKeys.current.add(item.key);
		const token = bumpToken(item.key);
		updateItem(item.key, {
			status: "queued",
			progress: null,
			error: "",
			duplicate: null,
			job: null,
			collectionError: "",
		});
		try {
			const gate = semaphore.current;
			if (gate === null) {
				return;
			}
			await runUploadPipeline({
				item,
				force,
				token,
				gate,
				shouldAbort: () =>
					stopped.current ||
					cancelledKeys.current.has(item.key) ||
					!isCurrent(item.key, token),
				isCurrent: () => isCurrent(item.key, token),
				update: (patch) => updateItem(item.key, patch),
				invalidateList,
				addToCollection,
			});
		} catch (error) {
			if (!isCurrent(item.key, token)) {
				return;
			}
			updateItem(item.key, {
				status: "error",
				progress: null,
				error: error instanceof ApiError ? error.message : "",
			});
		} finally {
			activeKeys.current.delete(item.key);
		}
	};

	const addFiles = (files: File[] | null) => {
		if (files === null || files.length === 0) {
			return;
		}
		const created: QueueItem[] = files.map((file) => {
			counter.current += 1;
			return {
				key: `${counter.current}-${file.name}`,
				file,
				type,
				status: "queued",
				progress: null,
				error: "",
				duplicate: null,
				job: null,
				collectionError: "",
			};
		});
		setItems((prev) => [...created, ...prev]);
		for (const item of created) {
			void processItem(item, false);
		}
	};

	const cancelItem = (item: QueueItem) => {
		cancelledKeys.current.add(item.key);
		bumpToken(item.key);
		if (item.job !== null) {
			void cancelUploadJob(item.job.kind, item.job.id).catch(() => undefined);
		}
		updateItem(item.key, { status: "cancelled", progress: null });
	};

	const removeItem = (item: QueueItem) => {
		cancelledKeys.current.add(item.key);
		bumpToken(item.key);
		// Убранная строка не должна оставлять висящий серверный джоб.
		if (item.job !== null) {
			void cancelUploadJob(item.job.kind, item.job.id).catch(() => undefined);
		}
		setItems((prev) => prev.filter((row) => row.key !== item.key));
	};

	const retryItem = (item: QueueItem) => {
		cancelledKeys.current.delete(item.key);
		void processItem(item, false);
	};

	const forceItem = (item: QueueItem) => {
		cancelledKeys.current.delete(item.key);
		void processItem(item, true);
	};

	// Уход со страницы: новые заливки не начинаем, поллинг старых
	// прекращаем тикетами. Серверные задания не отменяем.
	useEffect(() => {
		// StrictMode в dev прогоняет setup→cleanup→setup: сбрасываем флаг,
		// иначе после первого cleanup очередь навсегда «остановлена».
		stopped.current = false;
		const tokenMap = tokens.current;
		return () => {
			stopped.current = true;
			for (const key of tokenMap.keys()) {
				tokenMap.set(key, (tokenMap.get(key) ?? 0) + 1);
			}
		};
	}, []);

	const busy = items.some(
		(item) =>
			item.status === "queued" ||
			item.status === "uploading" ||
			item.status === "processing",
	);

	return {
		items,
		addFiles,
		cancelItem,
		removeItem,
		retryItem,
		forceItem,
		busy,
	};
}

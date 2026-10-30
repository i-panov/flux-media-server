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

const POLL_INTERVAL_MS = 900;

export type ItemStatus =
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

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => {
		setTimeout(resolve, ms);
	});
}

// Очередь загрузок: каждый файл обрабатывается независимо, ответы
// устаревших попыток отсекаются тикетом (отмена/повтор/force).
// targetCollectionId — коллекция экрана: готовый файл кладётся в неё
// сразу (как во Flutter), выбор читается на старте обработки.
export function useUploadQueue(
	type: UploadType,
	targetCollectionId: number | null,
) {
	const queryClient = useQueryClient();
	const { t } = useTranslation();
	const [items, setItems] = useState<QueueItem[]>([]);
	const counter = useRef(0);
	const tokens = useRef(new Map<string, number>());

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

	const processItem = async (item: QueueItem, force: boolean) => {
		const token = bumpToken(item.key);
		// Коллекция фиксируется на старте обработки (как во Flutter):
		// смена выбора посреди загрузки на летящий файл не влияет.
		const targetCollection = targetCollectionId;
		updateItem(item.key, {
			status: "uploading",
			progress: null,
			error: "",
			duplicate: null,
			job: null,
			collectionError: "",
		});
		try {
			const enqueued = await enqueueUpload(item.file, item.type, force);
			if (!isCurrent(item.key, token)) {
				// Отменили, пока запрос летел: задание всё же создано на
				// сервере — гасим его.
				void cancelUploadJob(enqueued.jobType, enqueued.jobId).catch(
					() => undefined,
				);
				return;
			}
			const job = { id: enqueued.jobId, kind: enqueued.jobType };
			updateItem(item.key, { status: "processing", job });
			while (true) {
				const status = await fetchUploadJob(job.kind, job.id);
				if (!isCurrent(item.key, token)) {
					return;
				}
				const progress =
					typeof status.progress === "number" ? status.progress : null;
				if (status.status === "done") {
					let collectionError = "";
					const mediaId = status.media?.id ?? null;
					if (targetCollection !== null && mediaId !== null) {
						try {
							await apiFetch<unknown>(
								`/collections/${targetCollection}/items`,
								{
									method: "POST",
									body: JSON.stringify({ media_id: mediaId }),
								},
							);
							void queryClient.invalidateQueries({
								queryKey: ["collections", targetCollection, "items"],
							});
						} catch (collectionFailure) {
							collectionError =
								collectionFailure instanceof ApiError &&
								collectionFailure.message !== ""
									? collectionFailure.message
									: t("upload.collectionErrorFallback");
						}
					}
					updateItem(item.key, {
						status: "done",
						progress: 100,
						collectionError,
					});
					invalidateList(item.type);
					return;
				}
				if (status.status === "duplicate") {
					updateItem(item.key, {
						status: "duplicate",
						progress: null,
						duplicate: status.duplicate ?? null,
					});
					return;
				}
				if (status.status === "error" || status.status === "cancelled") {
					updateItem(item.key, {
						status: status.status === "cancelled" ? "cancelled" : "error",
						progress: null,
						error: status.error ?? "",
					});
					return;
				}
				updateItem(item.key, { status: "processing", progress });
				await sleep(POLL_INTERVAL_MS);
			}
		} catch (error) {
			if (!isCurrent(item.key, token)) {
				return;
			}
			updateItem(item.key, {
				status: "error",
				progress: null,
				error: error instanceof ApiError ? error.message : "",
			});
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
				status: "uploading",
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
		bumpToken(item.key);
		if (item.job !== null) {
			void cancelUploadJob(item.job.kind, item.job.id).catch(() => undefined);
		}
		updateItem(item.key, { status: "cancelled", progress: null });
	};

	const removeItem = (item: QueueItem) => {
		bumpToken(item.key);
		// Убранная строка не должна оставлять висящий серверный джоб.
		if (item.job !== null) {
			void cancelUploadJob(item.job.kind, item.job.id).catch(() => undefined);
		}
		setItems((prev) => prev.filter((row) => row.key !== item.key));
	};

	const retryItem = (item: QueueItem) => {
		void processItem(item, false);
	};

	const forceItem = (item: QueueItem) => {
		void processItem(item, true);
	};

	// Уход со страницы останавливает опрос: задания на сервере не
	// отменяем, но ответы больше не трогают состояние.
	useEffect(() => {
		const map = tokens.current;
		return () => {
			for (const key of map.keys()) {
				map.set(key, (map.get(key) ?? 0) + 1);
			}
		};
	}, []);

	const busy = items.some(
		(item) => item.status === "uploading" || item.status === "processing",
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

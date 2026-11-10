// Чистые правила очереди загрузок: лимит параллельных POST и подписи
// прогресса. Вынесены из хука, чтобы проверяться в Node без React Native.

// Backend буферизует тело загрузки в RAM: десятки параллельных файлов
// могут положить инстанс. Слот держится только на время POST, поллинг
// серверной обработки идёт вне лимита.
export const MAX_PARALLEL_UPLOADS = 2;

export type UploadItemStatus =
	| "queued"
	| "uploading"
	| "processing"
	| "done"
	| "error"
	| "cancelled";

export interface UploadSemaphore {
	/** Сколько слотов занято прямо сейчас. */
	readonly active: number;
	/** Сколько задач ждёт свободный слот. */
	readonly pending: number;
	/** Ждёт слот и возвращает идемпотентный release. */
	acquire(): Promise<() => void>;
}

// Семафор FIFO: освободившийся слот получает самая ранняя ожидающая
// загрузка, а не случайная. Это важно для очереди из нескольких файлов:
// прогресс стартует по порядку выбора.
export function createUploadSemaphore(
	limit: number = MAX_PARALLEL_UPLOADS,
): UploadSemaphore {
	if (!Number.isInteger(limit) || limit <= 0) {
		throw new Error("Upload concurrency limit must be a positive integer");
	}
	const waiters: (() => void)[] = [];
	let active = 0;

	const admit = (): (() => void) => {
		active += 1;
		let released = false;
		return () => {
			if (released) {
				return;
			}
			released = true;
			active -= 1;
			const next = waiters.shift();
			if (next !== undefined) {
				next();
			}
		};
	};

	return {
		get active() {
			return active;
		},
		get pending() {
			return waiters.length;
		},
		acquire: () => {
			if (active < limit) {
				return Promise.resolve(admit());
			}
			return new Promise<() => void>((resolve) => {
				waiters.push(() => resolve(admit()));
			});
		},
	};
}

export function isActiveUploadStatus(status: UploadItemStatus): boolean {
	return (
		status === "queued" || status === "uploading" || status === "processing"
	);
}

// Человеческая подпись прогресса для строки очереди; null — сервер пока
// не сообщает прогресс (upload/transcode ещё не начался).
export function formatUploadProgress(
	progress: number | null | undefined,
): string {
	if (progress === null || progress === undefined) {
		return "—";
	}
	if (!Number.isFinite(progress)) {
		return "—";
	}
	const percent = Math.min(100, Math.max(0, Math.round(progress)));
	return `${percent}%`;
}

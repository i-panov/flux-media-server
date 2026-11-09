// Ограничитель одновременных заливок. Слот держится только на время
// POST /upload, а не на всё время серверной обработки/поллинга.
export interface UploadSemaphore {
	acquire(): Promise<void>;
	release(): void;
}

export function createUploadSemaphore(limit: number): UploadSemaphore {
	if (!Number.isInteger(limit) || limit < 1) {
		throw new Error("upload semaphore limit must be a positive integer");
	}
	let active = 0;
	const waiters: (() => void)[] = [];
	return {
		acquire: () =>
			new Promise<void>((resolve) => {
				const grant = () => {
					active += 1;
					resolve();
				};
				if (active < limit) {
					grant();
					return;
				}
				waiters.push(grant);
			}),
		release: () => {
			const next = waiters.shift();
			if (next !== undefined) {
				// Слот переходит ожидающему: active не уменьшаем.
				next();
				return;
			}
			if (active > 0) {
				active -= 1;
			}
		},
	};
}

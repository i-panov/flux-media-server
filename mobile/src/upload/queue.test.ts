import { describe, expect, it } from "vitest";
import {
	createUploadSemaphore,
	formatUploadProgress,
	isActiveUploadStatus,
	MAX_PARALLEL_UPLOADS,
} from "./queue";

function sleep(ms: number): Promise<void> {
	return new Promise((resolve) => {
		setTimeout(resolve, ms);
	});
}

describe("createUploadSemaphore", () => {
	it("держит не больше двух одновременных загрузок", async () => {
		const semaphore = createUploadSemaphore(MAX_PARALLEL_UPLOADS);
		let running = 0;
		let peak = 0;
		const tasks = Array.from({ length: 5 }, () =>
			(async () => {
				const release = await semaphore.acquire();
				running += 1;
				peak = Math.max(peak, running);
				await sleep(1);
				running -= 1;
				release();
			})(),
		);
		await Promise.all(tasks);
		expect(MAX_PARALLEL_UPLOADS).toBe(2);
		expect(peak).toBe(2);
		expect(running).toBe(0);
		expect(semaphore.active).toBe(0);
		expect(semaphore.pending).toBe(0);
	});

	it("отпускает слот самой ранней ожидающей задаче (FIFO)", async () => {
		const semaphore = createUploadSemaphore(2);
		const first = await semaphore.acquire();
		const second = await semaphore.acquire();
		const order: string[] = [];
		const a = semaphore.acquire().then((release) => {
			order.push("a");
			return release;
		});
		const b = semaphore.acquire().then((release) => {
			order.push("b");
			return release;
		});
		expect(semaphore.pending).toBe(2);

		first();
		const releaseA = await a;
		expect(order).toEqual(["a"]);
		expect(semaphore.active).toBe(2);

		releaseA();
		const releaseB = await b;
		expect(order).toEqual(["a", "b"]);
		releaseB();
		second();
		expect(semaphore.active).toBe(0);
	});

	it("повторный release не освобождает чужой слот", async () => {
		const semaphore = createUploadSemaphore(1);
		const release = await semaphore.acquire();
		release();
		release();
		expect(semaphore.active).toBe(0);
		const next = await semaphore.acquire();
		expect(semaphore.active).toBe(1);
		next();
	});

	it("не создаёт семафор с невалидным лимитом", () => {
		expect(() => createUploadSemaphore(0)).toThrow();
		expect(() => createUploadSemaphore(1.5)).toThrow();
	});
});

describe("formatUploadProgress", () => {
	it("показывает округлённые проценты", () => {
		expect(formatUploadProgress(0)).toBe("0%");
		expect(formatUploadProgress(42.4)).toBe("42%");
		expect(formatUploadProgress(42.6)).toBe("43%");
		expect(formatUploadProgress(100)).toBe("100%");
	});

	it("ограничивает значения диапазоном 0–100", () => {
		expect(formatUploadProgress(-5)).toBe("0%");
		expect(formatUploadProgress(150)).toBe("100%");
	});

	it("неизвестный прогресс — прочерк, а не ложный 0%", () => {
		expect(formatUploadProgress(null)).toBe("—");
		expect(formatUploadProgress(undefined)).toBe("—");
		expect(formatUploadProgress(Number.NaN)).toBe("—");
	});
});

describe("isActiveUploadStatus", () => {
	it("активными считаются только незавершённые состояния", () => {
		expect(isActiveUploadStatus("queued")).toBe(true);
		expect(isActiveUploadStatus("uploading")).toBe(true);
		expect(isActiveUploadStatus("processing")).toBe(true);
		expect(isActiveUploadStatus("done")).toBe(false);
		expect(isActiveUploadStatus("error")).toBe(false);
		expect(isActiveUploadStatus("cancelled")).toBe(false);
	});
});

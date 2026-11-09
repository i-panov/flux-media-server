import { describe, expect, it } from "vitest";
import { createUploadSemaphore } from "./uploadSemaphore";

describe("createUploadSemaphore", () => {
	it("держит не больше limit одновременных слотов", async () => {
		const semaphore = createUploadSemaphore(2);
		const started: number[] = [];

		const run = async (id: number) => {
			await semaphore.acquire();
			started.push(id);
		};

		await Promise.all([run(1), run(2)]);
		expect(started).toEqual([1, 2]);

		const third = run(3);
		await Promise.resolve();
		expect(started).toEqual([1, 2]);

		semaphore.release();
		await third;
		expect(started).toEqual([1, 2, 3]);
	});

	it("release без ожидающих освобождает слот", async () => {
		const semaphore = createUploadSemaphore(1);
		await semaphore.acquire();
		semaphore.release();
		await expect(semaphore.acquire()).resolves.toBeUndefined();
	});
});

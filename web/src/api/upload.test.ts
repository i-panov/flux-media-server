import { afterEach, describe, expect, it, vi } from "vitest";
import { cancelUploadJob, enqueueUpload, fetchUploadJob } from "./upload";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function emptyResponse(status = 204): Response {
	return new Response(null, { status });
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("upload api", () => {
	it("отправляет файл с типом и force, возвращает job", async () => {
		const fetchMock = vi
			.fn()
			.mockImplementation(() =>
				Promise.resolve(jsonResponse({ job_id: 7, job_type: "upload" })),
			);
		vi.stubGlobal("fetch", fetchMock);

		const file = new File(["image"], "meme.png", { type: "image/png" });
		await expect(enqueueUpload(file, "image")).resolves.toEqual({
			jobId: 7,
			jobType: "upload",
		});

		const first = fetchMock.mock.calls[0];
		if (first === undefined) {
			throw new Error("запрос не отправлен");
		}
		expect(String(first[0])).toBe("/api/media/upload");
		const firstInit = first[1] as RequestInit;
		expect(firstInit.method).toBe("POST");
		const firstForm = firstInit.body as FormData;
		expect(firstForm.get("media_type")).toBe("image");
		expect(firstForm.get("file")).toBe(file);
		expect(firstForm.has("force")).toBe(false);

		await enqueueUpload(file, "image", true);
		const second = fetchMock.mock.calls[1];
		if (second === undefined) {
			throw new Error("повторный запрос не отправлен");
		}
		const secondForm = (second[1] as RequestInit).body as FormData;
		expect(secondForm.get("force")).toBe("true");
	});

	it("без job_type считает видео транскодом", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ job_id: 3 })),
		);
		const file = new File(["video"], "movie.mp4", { type: "video/mp4" });
		await expect(enqueueUpload(file, "video")).resolves.toEqual({
			jobId: 3,
			jobType: "transcode",
		});
	});

	it("опрашивает нужный эндпоинт статуса", async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			jsonResponse({
				id: 1,
				status: "processing",
				error: null,
				media: null,
				progress: 42,
			}),
		);
		vi.stubGlobal("fetch", fetchMock);

		const status = await fetchUploadJob("transcode", 1);
		expect(status.status).toBe("processing");
		expect(status.progress).toBe(42);
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe(
			"/api/media/transcodes/1",
		);
	});

	it("разбирает duplicate и умеет отменять задание без тела", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(
				jsonResponse({
					id: 1,
					status: "duplicate",
					error: null,
					media: null,
					duplicate: { id: 4, title: "Старый мем" },
				}),
			)
			.mockResolvedValueOnce(emptyResponse());
		vi.stubGlobal("fetch", fetchMock);

		const status = await fetchUploadJob("upload", 1);
		expect(status.duplicate).toEqual({ id: 4, title: "Старый мем" });

		await expect(cancelUploadJob("upload", 1)).resolves.toBeUndefined();
		const cancelCall = fetchMock.mock.calls[1];
		if (cancelCall === undefined) {
			throw new Error("запрос отмены не отправлен");
		}
		expect(String(cancelCall[0])).toBe("/api/media/uploads/1");
		expect((cancelCall[1] as RequestInit).method).toBe("DELETE");
	});
});

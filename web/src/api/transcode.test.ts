import { afterEach, describe, expect, it, vi } from "vitest";
import {
	cancelTranscode,
	getTranscodeStatus,
	listTranscodes,
} from "./transcode";

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

describe("transcode api", () => {
	it("разбирает список заданий", async () => {
		const body = [
			{
				id: 2,
				status: "processing",
				progress: 40,
				speed: 1.5,
				eta_seconds: 30,
				error: null,
				filename: "movie.mp4",
				media_id: 3,
			},
		];
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse(body));
		vi.stubGlobal("fetch", fetchMock);

		await expect(listTranscodes()).resolves.toEqual(body);
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe(
			"/api/admin/transcodes",
		);
	});

	it("разбирает статус задания", async () => {
		const body = {
			id: 5,
			status: "processing",
			error: null,
			media: null,
			progress: 42,
			speed: 2,
			eta_seconds: 10,
		};
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(body)));

		const status = await getTranscodeStatus(5);
		expect(status.progress).toBe(42);
		expect(status.status).toBe("processing");
	});

	it("отменяет задание без тела", async () => {
		const fetchMock = vi.fn().mockResolvedValue(emptyResponse());
		vi.stubGlobal("fetch", fetchMock);

		await expect(cancelTranscode(5)).resolves.toBeUndefined();
		const call = fetchMock.mock.calls[0];
		if (call === undefined) {
			throw new Error("запрос не отправлен");
		}
		expect(String(call[0])).toBe("/api/media/transcodes/5");
		expect((call[1] as RequestInit).method).toBe("DELETE");
	});
});

import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchLyrics, saveLyrics } from "./lyrics";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function lyricsBody(mediaId: number) {
	return {
		id: 1,
		media_id: mediaId,
		lyrics_text: "line one",
		translation: "строка один",
		sync_data: "",
		source: "user",
		created_at: "2026-01-01T00:00:00Z",
		updated_at: "2026-01-01T00:00:00Z",
	};
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("fetchLyrics", () => {
	it("возвращает null, если текста нет", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "not found" }, 404)),
		);

		await expect(fetchLyrics(7)).resolves.toBeNull();
	});

	it("парсит текст, перевод и источник", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse(lyricsBody(7))),
		);

		await expect(fetchLyrics(7)).resolves.toMatchObject({
			media_id: 7,
			lyrics_text: "line one",
			translation: "строка один",
			source: "user",
		});
	});
});

describe("saveLyrics", () => {
	it("отправляет полное состояние с clear и source по умолчанию", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({}));
		vi.stubGlobal("fetch", fetchMock);

		await saveLyrics(7, { lyricsText: "new", translation: "" });

		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/media/7/lyrics");
		expect(init.method).toBe("PUT");
		expect(JSON.parse(init.body as string)).toEqual({
			lyrics_text: "new",
			translation: "",
			sync_data: "",
			source: "user",
			clear: true,
		});
	});

	it("сохраняет явные source и sync_data", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({}));
		vi.stubGlobal("fetch", fetchMock);

		await saveLyrics(7, {
			lyricsText: "new",
			translation: "перевод",
			syncData: "[00:01.00]new",
			source: "lrclib",
		});

		const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(JSON.parse(init.body as string)).toMatchObject({
			translation: "перевод",
			sync_data: "[00:01.00]new",
			source: "lrclib",
			clear: true,
		});
	});
});

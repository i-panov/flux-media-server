import { afterEach, describe, expect, it, vi } from "vitest";
import {
	deleteProgress,
	fetchContinueWatching,
	fetchLatestUnfinishedAudio,
	fetchProgress,
	isUnfinishedProgress,
	saveProgress,
} from "./progress";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function mediaItem(id: number, type = "video") {
	return {
		id,
		title: `Film ${id}`,
		filename: "",
		year: 2024,
		description: "",
		type,
		artists: [],
		album: "",
		genre: "",
		duration: 3600,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: "",
		view_count: 1,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "",
	};
}

function entry(
	id: number,
	mediaId: number,
	position: number,
	duration: number,
	completed = false,
	type = "video",
) {
	return {
		id,
		user_id: 1,
		media_id: mediaId,
		position,
		duration,
		completed,
		updated_at: "2026-01-01T00:00:00Z",
		media: mediaItem(mediaId, type),
	};
}

function progressBody(mediaId: number, position = 120) {
	return {
		id: 1,
		user_id: 1,
		media_id: mediaId,
		position,
		duration: 3600,
		completed: false,
		updated_at: "2026-01-01T00:00:00Z",
	};
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("fetchProgress", () => {
	it("возвращает null, если прогресса нет", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "not found" }, 404)),
		);

		await expect(fetchProgress(7)).resolves.toBeNull();
	});

	it("парсит запись прогресса", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse(progressBody(7, 300))),
		);

		await expect(fetchProgress(7)).resolves.toMatchObject({
			media_id: 7,
			position: 300,
		});
	});
});

describe("saveProgress", () => {
	it("отправляет позицию PUT-ом", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(progressBody(7, 250)));
		vi.stubGlobal("fetch", fetchMock);

		await saveProgress({
			mediaId: 7,
			position: 250,
			duration: 3600,
			completed: false,
		});

		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/progress/7");
		expect(init.method).toBe("PUT");
		expect(JSON.parse(init.body as string)).toEqual({
			position: 250,
			duration: 3600,
			completed: false,
		});
	});
});

describe("deleteProgress", () => {
	it("считает 404 успехом: прогресса и так нет", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "not found" }, 404)),
		);

		await expect(deleteProgress(7)).resolves.toBeUndefined();
	});
});

describe("isUnfinishedProgress", () => {
	it("отбрасывает завершённые и почти досмотренные записи", () => {
		expect(isUnfinishedProgress(entry(1, 10, 120, 3600))).toBe(true);
		expect(isUnfinishedProgress(entry(2, 11, 120, 3600, true))).toBe(false);
		expect(isUnfinishedProgress(entry(3, 12, 3500, 3600))).toBe(false);
		expect(isUnfinishedProgress(entry(4, 13, 0, 0))).toBe(false);
	});
});

describe("fetchContinueWatching", () => {
	it("оставляет только начатые недосмотренные записи нужного типа", async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			jsonResponse({
				items: [
					entry(1, 10, 120, 3600),
					entry(2, 11, 600, 3600, true),
					entry(3, 12, 3500, 3600),
					entry(4, 13, 0, 0),
					entry(5, 14, 0, 3600),
					{ ...entry(6, 15, 300, 3600), media: null },
					entry(7, 16, 120, 3600, false, "audio"),
				],
				total: 7,
				limit: 20,
				offset: 0,
			}),
		);
		vi.stubGlobal("fetch", fetchMock);

		const entries = await fetchContinueWatching("video");

		expect(entries.map((item) => item.media_id)).toEqual([10, 14]);
		const requested = new URL(
			String(fetchMock.mock.calls[0]?.[0] ?? ""),
			"http://localhost",
		);
		expect(requested.pathname).toBe("/api/progress");
		expect(requested.searchParams.get("type")).toBe("video");
		expect(requested.searchParams.get("limit")).toBe("20");
		expect(requested.searchParams.get("offset")).toBe("0");
	});

	it("для аудио берёт только аудио-записи", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(
				jsonResponse({
					items: [
						entry(1, 10, 120, 3600, false, "video"),
						entry(2, 11, 30, 240, false, "audio"),
						entry(3, 12, 200, 240, false, "audio"),
					],
					total: 3,
					limit: 20,
					offset: 0,
				}),
			),
		);

		const entries = await fetchContinueWatching("audio");

		expect(entries.map((item) => item.media_id)).toEqual([11, 12]);
	});
});

describe("fetchLatestUnfinishedAudio", () => {
	it("возвращает первый недослушанный трек", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(
				jsonResponse({
					items: [
						entry(1, 10, 240, 240, true, "audio"),
						entry(2, 11, 30, 240, false, "audio"),
					],
					total: 2,
					limit: 20,
					offset: 0,
				}),
			),
		);

		await expect(fetchLatestUnfinishedAudio()).resolves.toMatchObject({
			id: 11,
			type: "audio",
		});
	});

	it("возвращает null, если недослушанных треков нет", async () => {
		vi.stubGlobal(
			"fetch",
			vi
				.fn()
				.mockResolvedValue(
					jsonResponse({ items: [], total: 0, limit: 20, offset: 0 }),
				),
		);

		await expect(fetchLatestUnfinishedAudio()).resolves.toBeNull();
	});
});

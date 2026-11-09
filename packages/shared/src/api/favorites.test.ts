import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError } from "./client";
import {
	fetchFavoriteArtistIds,
	fetchFavoriteMedia,
	isStaleFavoriteError,
	toggleArtistFavorite,
	toggleFavorite,
} from "./favorites";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function mediaItem(id: number) {
	return {
		id,
		title: `Film ${id}`,
		year: 2024,
		description: "",
		type: "video",
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
	};
}

function favoriteEntry(
	id: number,
	mediaId: number | null,
	artistId: number | null,
) {
	return {
		id,
		user_id: 1,
		media_id: mediaId,
		artist_id: artistId,
		media: mediaId === null ? null : mediaItem(mediaId),
		created_at: "2026-01-01T00:00:00Z",
	};
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("fetchFavoriteMedia", () => {
	it("собирает медиа со всех страниц и фильтрует по типу", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(
				jsonResponse({
					items: [favoriteEntry(1, 10, null), favoriteEntry(2, 11, null)],
					total: 3,
					limit: 2,
					offset: 0,
				}),
			)
			.mockResolvedValueOnce(
				jsonResponse({
					items: [favoriteEntry(3, 12, null)],
					total: 3,
					limit: 2,
					offset: 2,
				}),
			);
		vi.stubGlobal("fetch", fetchMock);

		const media = await fetchFavoriteMedia("video");

		expect(media.map((item) => item.id)).toEqual([10, 11, 12]);
		const first = new URL(
			String(fetchMock.mock.calls[0]?.[0] ?? ""),
			"http://localhost",
		);
		expect(first.pathname).toBe("/api/favorites");
		expect(first.searchParams.get("type")).toBe("video");
		expect(first.searchParams.get("offset")).toBe("0");
		const second = new URL(
			String(fetchMock.mock.calls[1]?.[0] ?? ""),
			"http://localhost",
		);
		expect(second.searchParams.get("offset")).toBe("2");
	});
});

describe("fetchFavoriteArtistIds", () => {
	it("забирает только id артистов", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(
				jsonResponse({
					items: [
						favoriteEntry(1, null, 5),
						favoriteEntry(2, 10, null),
						favoriteEntry(3, null, 6),
					],
					total: 3,
					limit: 200,
					offset: 0,
				}),
			),
		);

		const ids = await fetchFavoriteArtistIds();

		expect([...ids]).toEqual([5, 6]);
	});
});

describe("isStaleFavoriteError", () => {
	it("распознаёт 409 на добавление и 404 на удаление", () => {
		expect(isStaleFavoriteError(new ApiError(409, "dup"), false)).toBe(true);
		expect(isStaleFavoriteError(new ApiError(404, "gone"), true)).toBe(true);
		expect(isStaleFavoriteError(new ApiError(409, "dup"), true)).toBe(false);
		expect(isStaleFavoriteError(new Error("network"), false)).toBe(false);
	});
});

describe("toggleFavorite", () => {
	it("считает POST 409 уже добавленным избранным", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "already" }, 409));
		vi.stubGlobal("fetch", fetchMock);

		await expect(toggleFavorite(1, false)).resolves.toBeUndefined();
		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/media/1/favorite");
		expect(init.method).toBe("POST");
	});

	it("считает DELETE 404 уже удалённым избранным", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "not found" }, 404));
		vi.stubGlobal("fetch", fetchMock);

		await expect(toggleFavorite(1, true)).resolves.toBeUndefined();
		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/media/1/favorite");
		expect(init.method).toBe("DELETE");
	});

	it("пробрасывает остальные ошибки", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "boom" }, 500)),
		);

		await expect(toggleFavorite(1, false)).rejects.toMatchObject({
			status: 500,
		});
	});
});

describe("toggleArtistFavorite", () => {
	it("добавляет артиста POST-ом с artist_id", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ id: 11 }));
		vi.stubGlobal("fetch", fetchMock);

		await toggleArtistFavorite(5, false);

		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/favorites/artist");
		expect(init.method).toBe("POST");
		expect(JSON.parse(init.body as string)).toEqual({ artist_id: 5 });
	});

	it("убирает артиста DELETE-ом с query-параметром", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ message: "removed" }));
		vi.stubGlobal("fetch", fetchMock);

		await toggleArtistFavorite(5, true);

		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/favorites/artist?artist_id=5");
		expect(init.method).toBe("DELETE");
	});

	it("считает POST 409 уже добавленным избранным", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "dup" }, 409)),
		);

		await expect(toggleArtistFavorite(5, false)).resolves.toBeUndefined();
	});
});

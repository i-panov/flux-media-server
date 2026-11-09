import { QueryClient } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
	audioListOptions,
	type CoreFetcher,
	fetchMediaById,
	fetchMediaList,
	fetchMediaSubs,
	imageListOptions,
	isSafeImageUrl,
	mediaOptions,
	mediaSubsOptions,
	videoListOptions,
} from "./media";

function videoItem(id: number) {
	return {
		id,
		title: `Film ${id}`,
		filename: `film-${id}.mkv`,
		year: 2024,
		description: "desc",
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
		view_count: 3,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "",
		unknown_future_field: "must-be-stripped",
	};
}

function audioItem(id: number) {
	return {
		...videoItem(id),
		type: "audio",
		title: `Song ${id}`,
		artists: [
			{ id: 3, name: "Artist", unknown_artist_field: "stripped" },
			{ id: 4, name: "Featuring" },
		],
		album: "Album",
		genre: "Rock",
	};
}

function listBody(ids: number[], total: number) {
	return {
		items: ids.map((id) => videoItem(id)),
		total,
		limit: 24,
		offset: 0,
	};
}

function stubFetcher(body: unknown, calls: string[] = []): CoreFetcher {
	return (path: string) => {
		calls.push(path);
		return Promise.resolve(body);
	};
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("fetchMediaList", () => {
	it("запрашивает type=video и режет неизвестные ключи", async () => {
		const calls: string[] = [];
		const page = await fetchMediaList(stubFetcher(listBody([1], 1), calls), {
			type: "video",
			q: "",
			limit: 24,
			offset: 0,
		});

		expect(calls).toHaveLength(1);
		expect(calls[0]).toContain("/media?");
		expect(calls[0]).toContain("type=video");
		expect(page.items[0]).not.toHaveProperty("unknown_future_field");
		expect(page.items[0]?.title).toBe("Film 1");
	});

	it("запрашивает type=audio и разбирает исполнителей с альбомом", async () => {
		const calls: string[] = [];
		const audio = {
			items: [audioItem(5)],
			total: 1,
			limit: 24,
			offset: 0,
		};
		const page = await fetchMediaList(stubFetcher(audio, calls), {
			type: "audio",
			q: "",
			limit: 24,
			offset: 0,
		});

		expect(calls[0]).toContain("type=audio");
		expect(page.items[0]?.type).toBe("audio");
		expect(page.items[0]?.artists).toEqual([
			{ id: 3, name: "Artist", has_cover: false, updated_at: "" },
			{ id: 4, name: "Featuring", has_cover: false, updated_at: "" },
		]);
		expect(page.items[0]?.album).toBe("Album");
		expect(page.items[0]?.genre).toBe("Rock");
	});

	it("передаёт поисковый запрос параметром q", async () => {
		const calls: string[] = [];
		await fetchMediaList(stubFetcher(listBody([], 0), calls), {
			type: "video",
			q: "матрица",
			limit: 24,
			offset: 0,
		});

		expect(calls[0]).toContain(`q=${encodeURIComponent("матрица")}`);
	});
});

describe("схема медиа", () => {
	it("нормализует отсутствующие artists и пустой альбом", async () => {
		// Старые записи и прогресс без Preload не содержат аудио-полей.
		const withoutAudioFields: Record<string, unknown> = { ...videoItem(9) };
		delete withoutAudioFields.artists;
		delete withoutAudioFields.album;
		delete withoutAudioFields.genre;
		const media = await fetchMediaById(stubFetcher(withoutAudioFields), 9);

		expect(media.artists).toEqual([]);
		expect(media.album).toBe("");
		expect(media.genre).toBe("");
	});
});

describe("fetchMediaList artist filter", () => {
	it("передаёт artist_id для серверного фильтра", async () => {
		const calls: string[] = [];
		await fetchMediaList(stubFetcher(listBody([1], 1), calls), {
			type: "audio",
			q: "",
			limit: 24,
			offset: 0,
			artistId: 5,
		});
		const requested = new URL(String(calls[0] ?? ""), "http://localhost");
		expect(requested.searchParams.get("artist_id")).toBe("5");
	});
});

describe("videoListOptions", () => {
	it("листает страницы через offset", async () => {
		const client = new QueryClient();
		const page = await client.fetchInfiniteQuery(
			videoListOptions(stubFetcher(listBody([1], 1)), ""),
		);

		expect(page.pages).toHaveLength(1);
		expect(page.pages[0]?.items[0]?.id).toBe(1);
	});

	it("останавливается на пустой странице при total больше offset", () => {
		const { getNextPageParam } = videoListOptions(
			stubFetcher(listBody([], 5)),
			"",
		);
		if (getNextPageParam === undefined) {
			throw new Error("expected getNextPageParam");
		}
		const empty = { items: [], total: 5, limit: 24, offset: 0 };
		expect(getNextPageParam(empty, [empty], 0, [0])).toBeUndefined();
	});

	it("продолжает при неполной непустой странице", () => {
		const { getNextPageParam } = videoListOptions(
			stubFetcher(listBody([1], 5)),
			"",
		);
		if (getNextPageParam === undefined) {
			throw new Error("expected getNextPageParam");
		}
		const partial = {
			items: [videoItem(1)],
			total: 5,
			limit: 24,
			offset: 0,
		};
		expect(getNextPageParam(partial, [partial], 0, [0])).toBe(1);
	});
});

describe("list sort defaults", () => {
	it("видео и аудио запрашиваются новыми сверху", async () => {
		for (const options of [
			(fetch: CoreFetcher) => videoListOptions(fetch, ""),
			(fetch: CoreFetcher) => audioListOptions(fetch, ""),
		]) {
			const calls: string[] = [];
			const client = new QueryClient();
			await client.fetchInfiniteQuery(
				options(stubFetcher(listBody([1], 1), calls)),
			);
			const requested = new URL(String(calls[0] ?? ""), "http://localhost");
			expect(requested.searchParams.get("sort")).toBe("desc");
		}
	});
});

describe("audioListOptions", () => {
	it("листает аудио через offset", async () => {
		const client = new QueryClient();
		const page = await client.fetchInfiniteQuery(
			audioListOptions(stubFetcher(listBody([1], 1)), ""),
		);

		expect(page.pages[0]?.items).toHaveLength(1);
	});
});

describe("imageListOptions", () => {
	it("запрашивает type=image и новые сверху", async () => {
		const calls: string[] = [];
		const images = [{ ...videoItem(7), type: "image", title: "Meme" }];
		const client = new QueryClient();
		const page = await client.fetchInfiniteQuery(
			imageListOptions(
				stubFetcher({ items: images, total: 1, limit: 24, offset: 0 }, calls),
				"",
			),
		);

		expect(page.pages[0]?.items[0]?.title).toBe("Meme");
		const requested = new URL(String(calls[0] ?? ""), "http://localhost");
		expect(requested.searchParams.get("type")).toBe("image");
		expect(requested.searchParams.get("sort")).toBe("desc");
	});
});

// biome-ignore lint/security/noSecrets: имя тестируемой функции, не секрет.
describe("isSafeImageUrl", () => {
	it("принимает http, https и относительные пути", () => {
		expect(isSafeImageUrl("https://cdn.example/cover.jpg")).toBe(true);
		expect(isSafeImageUrl("http://cdn.example/cover.jpg")).toBe(true);
		expect(isSafeImageUrl("/api/media/7/cover")).toBe(true);
		expect(isSafeImageUrl("covers/7.jpg")).toBe(true);
	});

	it("отклоняет пустое и чужие схемы", () => {
		expect(isSafeImageUrl("")).toBe(false);
		expect(isSafeImageUrl("javascript:alert(1)")).toBe(false);
		expect(isSafeImageUrl("data:image/png;base64,AAA")).toBe(false);
		expect(isSafeImageUrl("blob:https://example/uuid")).toBe(false);
		expect(isSafeImageUrl("ftp://example/cover.jpg")).toBe(false);
	});
});

// biome-ignore lint/security/noSecrets: имя тестируемой функции, не секрет.
describe("fetchMediaById", () => {
	it("возвращает детали по id", async () => {
		const media = await fetchMediaById(stubFetcher(videoItem(7)), 7);

		expect(media.id).toBe(7);
		expect(media.title).toBe("Film 7");
	});
});

describe("mediaOptions", () => {
	it("строит запрос с ключом медиа", async () => {
		const client = new QueryClient();
		const media = await client.fetchQuery(
			mediaOptions(stubFetcher(videoItem(7)), 7),
		);

		expect(media.id).toBe(7);
	});
});

describe("fetchMediaSubs", () => {
	it("возвращает дорожки субтитров", async () => {
		const subs = await fetchMediaSubs(
			stubFetcher([{ lang: "ru", url: "/api/media/7/subs/ru" }]),
			7,
		);

		expect(subs).toEqual([{ lang: "ru", url: "/api/media/7/subs/ru" }]);
	});
});

describe("mediaSubsOptions", () => {
	it("строит запрос с ключом субтитров", async () => {
		const client = new QueryClient();
		const subs = await client.fetchQuery(mediaSubsOptions(stubFetcher([]), 7));

		expect(subs).toEqual([]);
	});
});

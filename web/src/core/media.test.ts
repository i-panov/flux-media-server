import { QueryClient } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
	type CoreFetcher,
	fetchMediaById,
	fetchMediaSubs,
	fetchVideoList,
	mediaOptions,
	mediaSubsOptions,
	videoListOptions,
} from "./media";

function videoItem(id: number) {
	return {
		id,
		title: `Film ${id}`,
		year: 2024,
		description: "desc",
		type: "video",
		duration: 3600,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: "",
		view_count: 3,
		created_at: "2026-01-01T00:00:00Z",
		unknown_future_field: "must-be-stripped",
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

describe("fetchVideoList", () => {
	it("запрашивает type=video и режет неизвестные ключи", async () => {
		const calls: string[] = [];
		const page = await fetchVideoList(stubFetcher(listBody([1], 1), calls), {
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

	it("передаёт поисковый запрос параметром q", async () => {
		const calls: string[] = [];
		await fetchVideoList(stubFetcher(listBody([], 0), calls), {
			q: "матрица",
			limit: 24,
			offset: 0,
		});

		expect(calls[0]).toContain(`q=${encodeURIComponent("матрица")}`);
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

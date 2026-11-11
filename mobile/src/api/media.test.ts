import type { CoreFetcher } from "@flux/shared";
import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it } from "vitest";
import { audioSearchOptions, videoSearchOptions } from "./media";

function audioItem(id: number) {
	return {
		id,
		title: `Song ${id}`,
		filename: `song-${id}.mp3`,
		year: 2024,
		description: "desc",
		type: "audio",
		artists: [{ id: 3, name: "Artist" }],
		album: "Album",
		genre: "Rock",
		duration: 180,
		width: 0,
		height: 0,
		file_size: 100,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: "",
		view_count: 3,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "",
	};
}

function listBody(ids: number[], total: number) {
	return {
		items: ids.map(audioItem),
		total,
		limit: 24,
		offset: 0,
	};
}

function stubFetcher(body: unknown, calls: string[] = []): CoreFetcher {
	return (path) => {
		calls.push(path);
		return Promise.resolve(body);
	};
}

function requestedUrl(calls: string[]): URL {
	return new URL(String(calls[0] ?? ""), "http://localhost");
}

describe("videoSearchOptions", () => {
	it("передаёт нормализованный q и сортировку в запрос", async () => {
		const calls: string[] = [];
		const client = new QueryClient();
		await client.fetchInfiniteQuery(
			videoSearchOptions(
				stubFetcher(listBody([1], 1), calls),
				"  dune   part  ",
				"asc",
			),
		);

		const requested = requestedUrl(calls);
		expect(requested.searchParams.get("type")).toBe("video");
		expect(requested.searchParams.get("q")).toBe("dune part");
		expect(requested.searchParams.get("sort")).toBe("asc");
	});

	it("пробельный q даёт один запрос без q и пустой ключ", async () => {
		const calls: string[] = [];
		const client = new QueryClient();
		const options = videoSearchOptions(
			stubFetcher(listBody([], 0), calls),
			" \t ",
			"desc",
		);

		await client.fetchInfiniteQuery(options);

		expect(calls).toHaveLength(1);
		expect(requestedUrl(calls).searchParams.has("q")).toBe(false);
		expect(options.queryKey).toEqual(["media", "video", "", "desc", 0]);
	});

	it("смена q или sort начинает пагинацию заново с offset=0", async () => {
		const calls: string[] = [];
		const client = new QueryClient();
		const fetch = stubFetcher(listBody([1], 1), calls);

		await client.fetchInfiniteQuery(videoSearchOptions(fetch, "", "desc"));
		await client.fetchInfiniteQuery(videoSearchOptions(fetch, "dune", "desc"));
		await client.fetchInfiniteQuery(videoSearchOptions(fetch, "dune", "asc"));

		expect(calls).toHaveLength(3);
		expect(
			calls.map((call) =>
				new URL(call, "http://localhost").searchParams.get("offset"),
			),
		).toEqual(["0", "0", "0"]);
	});
});

describe("audioSearchOptions", () => {
	it("передаёт type=audio, q и sort без artist_id", async () => {
		const calls: string[] = [];
		const client = new QueryClient();
		await client.fetchInfiniteQuery(
			audioSearchOptions(stubFetcher(listBody([2], 1), calls), "rock", "asc"),
		);

		const requested = requestedUrl(calls);
		expect(requested.searchParams.get("type")).toBe("audio");
		expect(requested.searchParams.get("q")).toBe("rock");
		expect(requested.searchParams.get("sort")).toBe("asc");
		expect(requested.searchParams.get("artist_id")).toBeNull();
	});

	it("смена сортировки даёт отдельный query key", () => {
		const fetch = stubFetcher(listBody([], 0));
		const asc = audioSearchOptions(fetch, "rock", "asc");
		const desc = audioSearchOptions(fetch, "rock", "desc");

		expect(asc.queryKey).not.toEqual(desc.queryKey);
		expect(asc.queryKey).toContain("asc");
		expect(desc.queryKey).toContain("desc");
	});
});

import { QueryClient } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import { mediaOptions, videoListOptions } from "../core/media";
import { apiFetch } from "./client";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function videoItem(id: number) {
	return {
		id,
		title: `Film ${id}`,
		year: 2024,
		description: "desc",
		duration: 3600,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: "",
		view_count: 3,
		created_at: "2026-01-01T00:00:00Z",
	};
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("web media adapter", () => {
	it("привязывает список видео к same-origin /api", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(
				jsonResponse({ items: [], total: 0, limit: 24, offset: 0 }),
			);
		vi.stubGlobal("fetch", fetchMock);

		const client = new QueryClient();
		await client.fetchInfiniteQuery(videoListOptions(apiFetch, ""));

		expect(fetchMock).toHaveBeenCalledOnce();
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toContain("/api/media?");
	});

	it("привязывает детали к same-origin /api", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse(videoItem(7)));
		vi.stubGlobal("fetch", fetchMock);

		const client = new QueryClient();
		const media = await client.fetchQuery(mediaOptions(apiFetch, 7));

		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe("/api/media/7");
		expect(media.title).toBe("Film 7");
	});
});

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useContinueWatching } from "./progress";

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

function entry(
	id: number,
	mediaId: number,
	position: number,
	duration: number,
	completed = false,
) {
	return {
		id,
		user_id: 1,
		media_id: mediaId,
		position,
		duration,
		completed,
		updated_at: "2026-01-01T00:00:00Z",
		media: mediaItem(mediaId),
	};
}

const client = new QueryClient({
	defaultOptions: { queries: { retry: false } },
});

function TestWrapper({ children }: { children: ReactNode }) {
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

afterEach(() => {
	client.clear();
	vi.unstubAllGlobals();
});

describe("useContinueWatching", () => {
	it("оставляет только начатые и недосмотренные записи", async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			jsonResponse({
				items: [
					entry(1, 10, 120, 3600),
					{ ...entry(2, 11, 600, 3600, true) },
					// 97% — считаем просмотренным по порогу, не по флагу.
					entry(3, 12, 3500, 3600),
					// Ни позиции, ни длительности — показывать нечего.
					entry(4, 13, 0, 0),
					entry(5, 14, 0, 3600),
					// Медиа удалено: запись бесполезна.
					{ ...entry(6, 15, 300, 3600), media: null },
					// Прогресс по аудио пишет мобильный клиент: на странице
					// видео такой записи не место.
					{
						...entry(7, 16, 120, 3600),
						media: { ...mediaItem(16), type: "audio" },
					},
				],
				total: 7,
				limit: 20,
				offset: 0,
			}),
		);
		vi.stubGlobal("fetch", fetchMock);

		const { result } = renderHook(() => useContinueWatching(), {
			wrapper: TestWrapper,
		});

		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
		expect(result.current.data?.map((item) => item.media_id)).toEqual([10, 14]);
		// Biome принимает строку с query за секрет: сверяем URL по частям.
		const requested = new URL(
			String(fetchMock.mock.calls[0]?.[0] ?? ""),
			"http://localhost",
		);
		expect(requested.pathname).toBe("/api/progress");
		expect(requested.searchParams.get("limit")).toBe("20");
		expect(requested.searchParams.get("offset")).toBe("0");
	});
});

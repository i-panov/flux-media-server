import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useExtractAudio, useExtractedAudio } from "./extract";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function trackItem() {
	return {
		id: 9,
		title: "Извлечённый трек",
		filename: "track.mp3",
		year: 2024,
		description: "",
		type: "audio",
		artists: [],
		album: "",
		genre: "",
		duration: 120,
		width: 0,
		height: 0,
		file_size: 100,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
	};
}

const testClient = new QueryClient({
	defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
});

function TestWrapper({ children }: { children: ReactNode }) {
	return (
		<QueryClientProvider client={testClient}>{children}</QueryClientProvider>
	);
}

afterEach(() => {
	testClient.clear();
	vi.unstubAllGlobals();
});

describe("extract api", () => {
	it("404 извлечённого трека — это null, а не ошибка", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "No extracted track" }, 404));
		vi.stubGlobal("fetch", fetchMock);

		const { result } = renderHook(() => useExtractedAudio(7), {
			wrapper: TestWrapper,
		});
		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
		expect(result.current.data).toBeNull();
	});

	it("готовый трек из POST применяется без опроса", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse(trackItem()));
		vi.stubGlobal("fetch", fetchMock);

		const { result } = renderHook(() => useExtractAudio(7), {
			wrapper: TestWrapper,
		});
		let track: unknown = null;
		await act(async () => {
			track = await result.current.start();
		});
		expect((track as { id: number }).id).toBe(9);
		expect(result.current.isExtracting).toBe(false);
		expect(fetchMock).toHaveBeenCalledOnce();
	});

	it("ошибка старта показывает сообщение", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "ffmpeg not installed" }, 503));
		vi.stubGlobal("fetch", fetchMock);

		const { result } = renderHook(() => useExtractAudio(7), {
			wrapper: TestWrapper,
		});
		await act(async () => {
			await result.current.start();
		});
		expect(result.current.error).toBe("ffmpeg not installed");
		expect(result.current.isExtracting).toBe(false);
	});
});

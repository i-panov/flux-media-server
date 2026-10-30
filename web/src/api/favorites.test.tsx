import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useToggleArtistFavorite, useToggleFavorite } from "./favorites";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

const client = new QueryClient({
	defaultOptions: { mutations: { retry: false }, queries: { retry: false } },
});

function TestWrapper({ children }: { children: ReactNode }) {
	return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

afterEach(() => {
	client.clear();
	vi.unstubAllGlobals();
});

describe("useToggleFavorite", () => {
	it("считает POST 409 уже добавленным избранным", async () => {
		vi.stubGlobal(
			"fetch",
			vi
				.fn()
				.mockResolvedValue(
					jsonResponse({ message: "Already in favorites" }, 409),
				),
		);
		const { result } = renderHook(() => useToggleFavorite("video"), {
			wrapper: TestWrapper,
		});
		result.current.mutate({ mediaId: 1, favorite: false });
		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
	});

	it("считает DELETE 404 уже удалённым избранным", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "Not found" }, 404)),
		);
		const { result } = renderHook(() => useToggleFavorite("video"), {
			wrapper: TestWrapper,
		});
		result.current.mutate({ mediaId: 1, favorite: true });
		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
	});
});

describe("useToggleArtistFavorite", () => {
	it("добавляет артиста POST-ом с artist_id", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ id: 11 }));
		vi.stubGlobal("fetch", fetchMock);
		const { result } = renderHook(() => useToggleArtistFavorite(), {
			wrapper: TestWrapper,
		});
		result.current.mutate({ artistId: 5, favorite: false });
		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
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
		const { result } = renderHook(() => useToggleArtistFavorite(), {
			wrapper: TestWrapper,
		});
		result.current.mutate({ artistId: 5, favorite: true });
		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/favorites/artist?artist_id=5");
		expect(init.method).toBe("DELETE");
	});

	it("считает POST 409 уже добавленным избранным", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ message: "dup" }, 409)),
		);
		const { result } = renderHook(() => useToggleArtistFavorite(), {
			wrapper: TestWrapper,
		});
		result.current.mutate({ artistId: 5, favorite: false });
		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
	});
});

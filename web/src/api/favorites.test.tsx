import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useToggleFavorite } from "./favorites";

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

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, renderHook } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useDeleteMedia } from "./media";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
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

describe("useDeleteMedia", () => {
	it("отправляет DELETE на медиа", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ message: "Media moved to trash" }));
		vi.stubGlobal("fetch", fetchMock);

		const { result } = renderHook(() => useDeleteMedia(), {
			wrapper: TestWrapper,
		});
		await act(async () => {
			await result.current.mutateAsync(7);
		});

		expect(fetchMock).toHaveBeenCalledOnce();
		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/media/7");
		expect(init.method).toBe("DELETE");
	});

	it("пробрасывает ошибку сервера", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "Media not found" }, 404));
		vi.stubGlobal("fetch", fetchMock);

		const { result } = renderHook(() => useDeleteMedia(), {
			wrapper: TestWrapper,
		});
		await expect(result.current.mutateAsync(7)).rejects.toThrow(
			"Media not found",
		);
	});
});

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useDeleteUser, useRetryTranscode } from "./admin";

function emptyResponse(status = 204): Response {
	return new Response(null, { status });
}

function createClient(): QueryClient {
	return new QueryClient({
		defaultOptions: { mutations: { retry: false }, queries: { retry: false } },
	});
}

let activeClient: QueryClient | null = null;

function TestWrapper({ children }: { children: ReactNode }) {
	if (activeClient === null) {
		throw new Error("тестовый клиент не задан");
	}
	return (
		<QueryClientProvider client={activeClient}>{children}</QueryClientProvider>
	);
}

afterEach(() => {
	activeClient = null;
	vi.unstubAllGlobals();
	vi.restoreAllMocks();
});

describe("admin mutation wiring", () => {
	it("useRetryTranscode инвалидирует очередь транскодов", async () => {
		const fetchMock = vi.fn().mockResolvedValue(emptyResponse(202));
		vi.stubGlobal("fetch", fetchMock);
		const client = createClient();
		activeClient = client;
		const invalidateSpy = vi.spyOn(client, "invalidateQueries");

		const { result } = renderHook(() => useRetryTranscode(), {
			wrapper: TestWrapper,
		});
		result.current.mutate(7);

		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe(
			"/api/admin/transcodes/7/retry",
		);
		await waitFor(() => {
			expect(invalidateSpy).toHaveBeenCalledWith({
				queryKey: ["admin", "transcodes"],
			});
		});
	});

	it("useDeleteUser инвалидирует список пользователей", async () => {
		const fetchMock = vi.fn().mockResolvedValue(emptyResponse());
		vi.stubGlobal("fetch", fetchMock);
		const client = createClient();
		activeClient = client;
		const invalidateSpy = vi.spyOn(client, "invalidateQueries");

		const { result } = renderHook(() => useDeleteUser(), {
			wrapper: TestWrapper,
		});
		result.current.mutate(2);

		await waitFor(() => {
			expect(result.current.isSuccess).toBe(true);
		});
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe(
			"/api/admin/users/2",
		);
		await waitFor(() => {
			expect(invalidateSpy).toHaveBeenCalledWith({
				queryKey: ["admin", "users"],
			});
		});
	});
});

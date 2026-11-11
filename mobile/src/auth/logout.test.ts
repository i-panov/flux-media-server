import { QueryClient, QueryObserver } from "@tanstack/react-query";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { signOutLocal } from "./logout";
import { sessionQueryKey } from "./session";

const mocks = vi.hoisted(() => ({
	del: vi.fn(),
	logout: vi.fn(),
	accessKey: "flux.access",
	refreshKey: "flux.refresh",
}));

vi.mock("@flux/shared", () => ({
	ACCESS_TOKEN_KEY: mocks.accessKey,
	REFRESH_TOKEN_KEY: mocks.refreshKey,
	logout: mocks.logout,
}));

vi.mock("../storage/secureStore", () => ({
	secureStore: { del: mocks.del },
}));

describe("локальный выход", () => {
	beforeEach(() => {
		mocks.del.mockReset();
		mocks.logout.mockReset();
		mocks.del.mockResolvedValue(undefined);
		mocks.logout.mockResolvedValue(undefined);
	});

	it("удаляет оба токена, кэш запросов и сессию", async () => {
		const client = new QueryClient();
		client.setQueryData(["media", "list"], [1, 2]);
		const cancelQueries = vi.spyOn(client, "cancelQueries");
		const removeQueries = vi.spyOn(client, "removeQueries");
		const setQueryData = vi.spyOn(client, "setQueryData");

		await signOutLocal(client);

		expect(mocks.logout).toHaveBeenCalledTimes(1);
		expect(mocks.del).toHaveBeenNthCalledWith(1, mocks.accessKey);
		expect(mocks.del).toHaveBeenNthCalledWith(2, mocks.refreshKey);
		expect(cancelQueries).toHaveBeenCalledWith();
		expect(removeQueries).toHaveBeenCalledTimes(1);
		expect(setQueryData).toHaveBeenCalledWith(sessionQueryKey, null);
		expect(client.getQueryData(["media", "list"])).toBeUndefined();
	});

	it("mounted observer видит session=null после выхода", async () => {
		const client = new QueryClient();
		client.setQueryData(sessionQueryKey, {
			id: 1,
			email: "user@example.com",
			is_admin: false,
		});
		const seen: unknown[] = [];
		const observer = new QueryObserver(client, {
			queryKey: sessionQueryKey,
			queryFn: async () => null,
			staleTime: Number.POSITIVE_INFINITY,
		});
		const unsubscribe = observer.subscribe((result) => {
			seen.push(result.data);
		});

		await signOutLocal(client);

		expect(seen).toContain(null);
		expect(client.getQueryData(sessionQueryKey)).toBeNull();
		unsubscribe();
	});

	it("не ждёт серверный logout и очищает локальное состояние", async () => {
		// Промис не резолвится: если signOutLocal его ждёт, тест зависнет.
		mocks.logout.mockReturnValue(new Promise<void>(() => undefined));
		const client = new QueryClient();

		await expect(signOutLocal(client)).resolves.toBeUndefined();

		expect(mocks.del).toHaveBeenCalledTimes(2);
		expect(client.getQueryData(sessionQueryKey)).toBeNull();
	});

	it("удаляет оба токена, даже если первый SecureStore.del упал", async () => {
		mocks.del.mockImplementation((key: string) =>
			key === mocks.accessKey
				? Promise.reject(new Error("access storage"))
				: Promise.resolve(),
		);
		const client = new QueryClient();

		await signOutLocal(client);

		expect(mocks.del).toHaveBeenNthCalledWith(1, mocks.accessKey);
		expect(mocks.del).toHaveBeenNthCalledWith(2, mocks.refreshKey);
		expect(client.getQueryData(sessionQueryKey)).toBeNull();
	});

	it("очищает кэш и сессию, даже если SecureStore недоступен", async () => {
		mocks.del.mockRejectedValue(new Error("storage"));
		const client = new QueryClient();

		await signOutLocal(client);

		expect(mocks.del).toHaveBeenCalledTimes(2);
		expect(client.getQueryData(sessionQueryKey)).toBeNull();
	});
});

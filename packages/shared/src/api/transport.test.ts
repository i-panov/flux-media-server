import { afterEach, describe, expect, it, vi } from "vitest";
import type { KeyValueStore } from "../storage";
import {
	ACCESS_TOKEN_KEY,
	createTokenTransport,
	createWebTransport,
	getApiConfig,
	REFRESH_TOKEN_KEY,
	resetApiConfig,
} from "./transport";

function memoryStore(seed: Record<string, string> = {}): KeyValueStore {
	const map = new Map(Object.entries(seed));
	return {
		get: (key) => Promise.resolve(map.get(key) ?? null),
		set: (key, value) => {
			map.set(key, value);
			return Promise.resolve();
		},
		del: (key) => {
			map.delete(key);
			return Promise.resolve();
		},
	};
}

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("configureApi", () => {
	it("по умолчанию ведёт себя как веб: /api и same-origin", async () => {
		resetApiConfig();
		const config = getApiConfig();
		expect(config.baseUrl).toBe("/api");
		expect(await config.transport.authHeaders()).toEqual({});
		expect(config.transport.credentials()).toBe("same-origin");
	});

	it("токенный транспорт подставляет Bearer из хранилища", async () => {
		const transport = createTokenTransport(
			memoryStore({ "flux.access_token": "abc" }),
		);
		expect(await transport.authHeaders()).toEqual({
			Authorization: "Bearer abc",
		});
		expect(transport.credentials()).toBeUndefined();
	});

	it("токенный транспорт без токена не ставит заголовок", async () => {
		const transport = createTokenTransport(memoryStore());
		expect(await transport.authHeaders()).toEqual({});
	});

	it("createWebTransport помечает credentials, токенов не касается", async () => {
		const transport = createWebTransport();
		expect(await transport.authHeaders()).toEqual({});
		expect(transport.credentials()).toBe("same-origin");
	});

	it("getApiConfig возвращает копию: мутация не трогает глобальный конфиг", () => {
		resetApiConfig();
		getApiConfig().baseUrl = "https://evil.example";
		expect(getApiConfig().baseUrl).toBe("/api");
	});
});

describe("createTokenTransport.refresh", () => {
	it("успех сохраняет пару токенов в хранилище", async () => {
		const store = memoryStore({ [REFRESH_TOKEN_KEY]: "old-refresh" });
		const fetchMock = vi
			.fn()
			.mockResolvedValue(
				jsonResponse({ token: "new-access", refresh_token: "new-refresh" }),
			);
		vi.stubGlobal("fetch", fetchMock);
		const transport = createTokenTransport(store);

		await transport.refresh("https://example.com/api");

		expect(fetchMock).toHaveBeenCalledWith(
			"https://example.com/api/auth/refresh",
			expect.objectContaining({
				method: "POST",
				body: JSON.stringify({ refresh_token: "old-refresh" }),
			}),
		);
		await expect(store.get(ACCESS_TOKEN_KEY)).resolves.toBe("new-access");
		await expect(store.get(REFRESH_TOKEN_KEY)).resolves.toBe("new-refresh");
	});

	it("без сохранённого refresh-токена не ходит в сеть", async () => {
		const fetchMock = vi.fn();
		vi.stubGlobal("fetch", fetchMock);
		const transport = createTokenTransport(memoryStore());

		await expect(transport.refresh("https://example.com/api")).rejects.toThrow(
			"No refresh token stored",
		);
		expect(fetchMock).not.toHaveBeenCalled();
	});

	it.each([400, 401])("мёртвый refresh %d чистит пару", async (status) => {
		const store = memoryStore({
			[ACCESS_TOKEN_KEY]: "old-access",
			[REFRESH_TOKEN_KEY]: "old-refresh",
		});
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "revoked" }, status)),
		);
		const transport = createTokenTransport(store);

		await expect(transport.refresh("https://example.com/api")).rejects.toThrow(
			`Token refresh failed: ${status}`,
		);
		await expect(store.get(ACCESS_TOKEN_KEY)).resolves.toBeNull();
		await expect(store.get(REFRESH_TOKEN_KEY)).resolves.toBeNull();
	});

	it.each([500, 502])(
		"временный сбой refresh %d сохраняет пару",
		async (status) => {
			const store = memoryStore({
				[ACCESS_TOKEN_KEY]: "old-access",
				[REFRESH_TOKEN_KEY]: "old-refresh",
			});
			vi.stubGlobal(
				"fetch",
				vi.fn().mockResolvedValue(jsonResponse({ error: "boom" }, status)),
			);
			const transport = createTokenTransport(store);

			await expect(
				transport.refresh("https://example.com/api"),
			).rejects.toThrow(`Token refresh failed: ${status}`);
			await expect(store.get(ACCESS_TOKEN_KEY)).resolves.toBe("old-access");
			await expect(store.get(REFRESH_TOKEN_KEY)).resolves.toBe("old-refresh");
		},
	);

	it("сетевой сбой сохраняет пару", async () => {
		const store = memoryStore({
			[ACCESS_TOKEN_KEY]: "old-access",
			[REFRESH_TOKEN_KEY]: "old-refresh",
		});
		vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));
		const transport = createTokenTransport(store);

		await expect(transport.refresh("https://example.com/api")).rejects.toThrow(
			"offline",
		);
		await expect(store.get(ACCESS_TOKEN_KEY)).resolves.toBe("old-access");
		await expect(store.get(REFRESH_TOKEN_KEY)).resolves.toBe("old-refresh");
	});

	it.each([
		["пустое тело", new Response("", { status: 200 })],
		["null", jsonResponse(null)],
		["без полей", jsonResponse({})],
		["пустые строки", jsonResponse({ token: "", refresh_token: "" })],
	])("кривое тело %s даёт malformed-ошибку", async (_, response) => {
		const store = memoryStore({
			[ACCESS_TOKEN_KEY]: "old-access",
			[REFRESH_TOKEN_KEY]: "old-refresh",
		});
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response));
		const transport = createTokenTransport(store);

		await expect(transport.refresh("https://example.com/api")).rejects.toThrow(
			"Token refresh failed: malformed response",
		);
		await expect(store.get(ACCESS_TOKEN_KEY)).resolves.toBe("old-access");
		await expect(store.get(REFRESH_TOKEN_KEY)).resolves.toBe("old-refresh");
	});
});

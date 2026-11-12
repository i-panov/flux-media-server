import { QueryClient } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import { fetchMe, logout, requestCode, verifyCode } from "./auth";
import { sessionQueryOptions } from "./session";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

const testUser = { id: 7, email: "user@example.com", is_admin: false };

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("requestCode", () => {
	it("отправляет email и разбирает ответ", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(
				jsonResponse({ message: "Code sent successfully", code: "123456" }),
			);
		vi.stubGlobal("fetch", fetchMock);

		await expect(requestCode("user@example.com")).resolves.toEqual({
			message: "Code sent successfully",
			code: "123456",
		});
		expect(fetchMock).toHaveBeenCalledWith(
			"/api/auth/request-code",
			expect.objectContaining({
				method: "POST",
				body: JSON.stringify({ email: "user@example.com" }),
			}),
		);
	});
});

describe("verifyCode", () => {
	it("отправляет пару email+код и разбирает токены", async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			jsonResponse({
				token: "access",
				refresh_token: "refresh",
				user: testUser,
			}),
		);
		vi.stubGlobal("fetch", fetchMock);

		await expect(verifyCode("user@example.com", "123456")).resolves.toEqual({
			token: "access",
			refresh_token: "refresh",
			user: testUser,
		});
		expect(fetchMock).toHaveBeenCalledWith(
			"/api/auth/verify-code",
			expect.objectContaining({
				method: "POST",
				body: JSON.stringify({
					email: "user@example.com",
					code: "123456",
					device_id: "",
					device_name: "",
					platform: "",
				}),
			}),
		);
	});
});

describe("fetchMe", () => {
	it("разбирает пользователя", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(testUser)));

		await expect(fetchMe()).resolves.toEqual(testUser);
	});

	it("пробрасывает 401 как ApiError", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "Unauthorized" }, 401)),
		);

		await expect(fetchMe()).rejects.toMatchObject({ status: 401 });
	});
});

describe("logout", () => {
	it("отправляет refresh текущего устройства", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ message: "ok" }));
		vi.stubGlobal("fetch", fetchMock);

		await expect(logout()).resolves.toBeUndefined();
		expect(fetchMock).toHaveBeenCalledWith(
			"/api/auth/logout",
			expect.objectContaining({
				method: "POST",
				body: JSON.stringify({ refresh_token: "" }),
			}),
		);
	});
});

describe("sessionQueryOptions", () => {
	it("возвращает null при 401 вместо ошибки", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "Unauthorized" }, 401)),
		);
		const queryClient = new QueryClient({
			defaultOptions: { queries: { retry: false } },
		});

		await expect(
			queryClient.fetchQuery(sessionQueryOptions()),
		).resolves.toBeNull();
	});

	it("возвращает пользователя при живой сессии", async () => {
		vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse(testUser)));
		const queryClient = new QueryClient({
			defaultOptions: { queries: { retry: false } },
		});

		await expect(
			queryClient.fetchQuery(sessionQueryOptions()),
		).resolves.toEqual(testUser);
	});

	it("500 превращается в ошибку, а не в гостя", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "boom" }, 500)),
		);
		const queryClient = new QueryClient({
			defaultOptions: { queries: { retry: false } },
		});

		await expect(
			queryClient.fetchQuery(sessionQueryOptions()),
		).rejects.toMatchObject({ status: 500 });
	});

	it("сетевая ошибка превращается в ошибку, а не в гостя", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockRejectedValue(new TypeError("network down")),
		);
		const queryClient = new QueryClient({
			defaultOptions: { queries: { retry: false } },
		});

		await expect(queryClient.fetchQuery(sessionQueryOptions())).rejects.toThrow(
			TypeError,
		);
	});
});

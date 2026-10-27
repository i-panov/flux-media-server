import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, apiFetch, getHealth } from "./client";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("getHealth", () => {
	it("возвращает версию сервера", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ status: "ok", version: "1.0.8" }));
		vi.stubGlobal("fetch", fetchMock);

		await expect(getHealth()).resolves.toEqual({
			status: "ok",
			version: "1.0.8",
		});
		expect(fetchMock).toHaveBeenCalledWith(
			"/api/health",
			expect.objectContaining({ credentials: "same-origin" }),
		);
	});

	it("отклоняет ответ без обязательных полей", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ status: "ok" })),
		);

		await expect(getHealth()).rejects.toThrow();
	});
});

describe("apiFetch", () => {
	it("пробрасывает сообщение сервера", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "nope" }, 500)),
		);

		await expect(apiFetch("/x")).rejects.toMatchObject({
			status: 500,
			message: "nope",
		});
	});

	it("подставляет HTTP-статус, если тела нет", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(new Response("", { status: 502 })),
		);

		const error: unknown = await apiFetch("/x").catch(
			(reason: unknown) => reason,
		);

		expect(error).toBeInstanceOf(ApiError);
		expect(error).toMatchObject({ status: 502, message: "HTTP 502" });
	});

	it("не перезаписывает переданный credentials", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ ok: true }));
		vi.stubGlobal("fetch", fetchMock);

		await apiFetch("/x", { credentials: "include" });

		expect(fetchMock).toHaveBeenCalledWith(
			"/api/x",
			expect.objectContaining({ credentials: "include" }),
		);
	});
});

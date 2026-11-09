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

	it("обновляет токены и повторяет запрос при 401", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(jsonResponse({ error: "expired" }, 401))
			.mockResolvedValueOnce(jsonResponse({ ok: true }))
			.mockResolvedValueOnce(jsonResponse({ ok: true }));
		vi.stubGlobal("fetch", fetchMock);

		await expect(apiFetch("/x")).resolves.toEqual({ ok: true });
		expect(fetchMock).toHaveBeenNthCalledWith(
			2,
			"/api/auth/refresh",
			expect.objectContaining({ method: "POST", body: "{}" }),
		);
		expect(fetchMock).toHaveBeenCalledTimes(3);
	});

	it("пробрасывает исходный 401, если refresh не удался", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(jsonResponse({ error: "expired" }, 401))
			.mockResolvedValueOnce(jsonResponse({ error: "revoked" }, 401));
		vi.stubGlobal("fetch", fetchMock);

		await expect(apiFetch("/x")).rejects.toMatchObject({
			status: 401,
			message: "expired",
		});
		expect(fetchMock).toHaveBeenCalledTimes(2);
	});

	it("не маскирует сетевой сбой refresh под 401", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(jsonResponse({ error: "expired" }, 401))
			.mockResolvedValueOnce(jsonResponse({ error: "boom" }, 500));
		vi.stubGlobal("fetch", fetchMock);

		await expect(apiFetch("/x")).rejects.not.toMatchObject({
			status: 401,
		});
		expect(fetchMock).toHaveBeenCalledTimes(2);
	});

	it("не обновляет токены для публичных auth-эндпоинтов", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "expired" }, 401));
		vi.stubGlobal("fetch", fetchMock);

		await expect(
			apiFetch("/auth/refresh", { method: "POST", body: "{}" }),
		).rejects.toMatchObject({ status: 401 });
		expect(fetchMock).toHaveBeenCalledTimes(1);
	});

	it("один refresh на пачку параллельных 401", async () => {
		let dataCalls = 0;
		const fetchMock = vi.fn((input: unknown) => {
			const url = String(input);
			if (url.endsWith("/auth/refresh")) {
				return Promise.resolve(jsonResponse({ ok: true }));
			}
			dataCalls += 1;
			return Promise.resolve(
				dataCalls <= 2
					? jsonResponse({ error: "expired" }, 401)
					: jsonResponse({ ok: true }),
			);
		});
		vi.stubGlobal("fetch", fetchMock);

		const [first, second] = await Promise.all([apiFetch("/x"), apiFetch("/y")]);

		expect(first).toEqual({ ok: true });
		expect(second).toEqual({ ok: true });
		const refreshCalls = fetchMock.mock.calls.filter((args) =>
			String(args[0]).endsWith("/auth/refresh"),
		);
		expect(refreshCalls).toHaveLength(1);
	});
});

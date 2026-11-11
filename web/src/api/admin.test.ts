import { afterEach, describe, expect, it, vi } from "vitest";
import {
	deleteOriginal,
	deleteUser,
	downloadOriginal,
	getStorage,
	listOriginals,
	listUsers,
	retryTranscode,
	setAutoCleanup,
	setUserAdmin,
} from "./admin";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function emptyResponse(status = 204): Response {
	return new Response(null, { status });
}

const storageBody = {
	disks: [{ path: "/data", total_bytes: 100, free_bytes: 5, used_bytes: 7 }],
	video_bytes: 10,
	audio_bytes: 20,
	originals_bytes: 30,
	temp_bytes: 40,
	auto_cleanup: true,
};

const originalsBody = [
	{
		name: "movie.mp4",
		size_bytes: 100,
		modified: "2026-01-01T00:00:00Z",
		status: "done",
		media_id: 3,
		views: 5,
	},
];

const usersBody = [
	{
		id: 1,
		email: "a@example.com",
		is_admin: true,
		created_at: "2026-01-01T00:00:00Z",
	},
];

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("admin api", () => {
	it("разбирает сводку диска", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse(storageBody));
		vi.stubGlobal("fetch", fetchMock);

		await expect(getStorage()).resolves.toEqual(storageBody);
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe(
			"/api/admin/storage",
		);
	});

	it("переключает авточистку оригиналов", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ auto_cleanup: false }));
		vi.stubGlobal("fetch", fetchMock);

		await expect(setAutoCleanup(false)).resolves.toEqual({
			auto_cleanup: false,
		});
		const call = fetchMock.mock.calls[0];
		if (call === undefined) {
			throw new Error("запрос не отправлен");
		}
		expect(String(call[0])).toBe("/api/admin/storage/settings");
		expect((call[1] as RequestInit).method).toBe("PUT");
		expect((call[1] as RequestInit).body).toBe(
			JSON.stringify({ auto_cleanup: false }),
		);
	});

	it("разбирает карантин оригиналов", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse(originalsBody)),
		);

		await expect(listOriginals()).resolves.toEqual(originalsBody);
	});

	it("удаляет оригинал без тела", async () => {
		const fetchMock = vi.fn().mockResolvedValue(emptyResponse());
		vi.stubGlobal("fetch", fetchMock);

		await expect(deleteOriginal("movie.mp4")).resolves.toBeUndefined();
		const call = fetchMock.mock.calls[0];
		if (call === undefined) {
			throw new Error("запрос не отправлен");
		}
		expect(String(call[0])).toBe("/api/admin/originals/movie.mp4");
		expect((call[1] as RequestInit).method).toBe("DELETE");
	});

	it("кодирует имя файла при удалении", async () => {
		const fetchMock = vi.fn().mockResolvedValue(emptyResponse());
		vi.stubGlobal("fetch", fetchMock);

		await deleteOriginal("a/b.mp4");
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe(
			"/api/admin/originals/a%2Fb.mp4",
		);
	});

	it("скачивает оригинал как blob", async () => {
		const blob = new Blob(["data"]);
		const fetchMock = vi.fn().mockResolvedValue({
			ok: true,
			status: 200,
			blob: () => Promise.resolve(blob),
		});
		vi.stubGlobal("fetch", fetchMock);

		const result = await downloadOriginal("movie.mp4");
		expect(await result.text()).toBe("data");
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe(
			"/api/admin/originals/movie.mp4/download",
		);
	});

	it("ставит задание на ретрай", async () => {
		const fetchMock = vi.fn().mockResolvedValue(emptyResponse(202));
		vi.stubGlobal("fetch", fetchMock);

		await expect(retryTranscode(7)).resolves.toBeUndefined();
		const call = fetchMock.mock.calls[0];
		if (call === undefined) {
			throw new Error("запрос не отправлен");
		}
		expect(String(call[0])).toBe("/api/admin/transcodes/7/retry");
		expect((call[1] as RequestInit).method).toBe("POST");
	});

	it("разбирает пользователей и меняет роль", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(jsonResponse(usersBody))
			.mockResolvedValueOnce(jsonResponse(usersBody[0]));
		vi.stubGlobal("fetch", fetchMock);

		await expect(listUsers()).resolves.toEqual(usersBody);
		await expect(setUserAdmin(1, false)).resolves.toEqual(usersBody[0]);

		const second = fetchMock.mock.calls[1];
		if (second === undefined) {
			throw new Error("запрос не отправлен");
		}
		expect(String(second[0])).toBe("/api/admin/users/1");
		expect((second[1] as RequestInit).method).toBe("PUT");
		expect((second[1] as RequestInit).body).toBe(
			JSON.stringify({ is_admin: false }),
		);
	});

	it("удаляет пользователя без тела", async () => {
		const fetchMock = vi.fn().mockResolvedValue(emptyResponse());
		vi.stubGlobal("fetch", fetchMock);

		await expect(deleteUser(2)).resolves.toBeUndefined();
		expect(String(fetchMock.mock.calls[0]?.[0] ?? "")).toBe(
			"/api/admin/users/2",
		);
	});
});

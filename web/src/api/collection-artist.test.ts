import { afterEach, describe, expect, it, vi } from "vitest";
import { moveCollection } from "./collections";
import { renameArtist } from "./metadata";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("moveCollection", () => {
	it("отправляет parent_id явно, включая null для корня", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ id: 2 }));
		vi.stubGlobal("fetch", fetchMock);

		await moveCollection(2, null);

		expect(fetchMock).toHaveBeenCalledOnce();
		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/collections/2");
		expect(init.method).toBe("PUT");
		// Ключ обязан присутствовать: отсутствие бэкенд читает как «не трогать».
		expect(JSON.parse(init.body as string)).toEqual({ parent_id: null });
	});

	it("переезд под родителя шлёт его id", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ id: 2 }));
		vi.stubGlobal("fetch", fetchMock);

		await moveCollection(2, 1);

		const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(JSON.parse(init.body as string)).toEqual({ parent_id: 1 });
	});
});

describe("renameArtist", () => {
	it("отправляет PUT с именем и разбирает ответ", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ id: 1, name: "Новое имя" }));
		vi.stubGlobal("fetch", fetchMock);

		const artist = await renameArtist(1, "Новое имя");

		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/artists/1");
		expect(init.method).toBe("PUT");
		expect(JSON.parse(init.body as string)).toEqual({ name: "Новое имя" });
		expect(artist).toEqual({ id: 1, name: "Новое имя" });
	});

	it("пробрасывает конфликт занятого имени", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "taken" }, 409));
		vi.stubGlobal("fetch", fetchMock);

		await expect(renameArtist(1, "Чужое имя")).rejects.toThrow("taken");
	});
});

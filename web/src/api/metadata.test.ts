import { afterEach, describe, expect, it, vi } from "vitest";
import { updateMetadata } from "./metadata";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function mediaItem() {
	return {
		id: 7,
		title: "Новое название",
		year: 2024,
		description: "",
		type: "video",
		artists: [{ id: 1, name: "Исполнитель" }],
		album: "Альбом",
		genre: "Жанр",
		duration: 3600,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: "",
		cover_url: "",
		view_count: 3,
		created_at: "2026-01-01T00:00:00Z",
	};
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("updateMetadata", () => {
	it("отправляет PUT с заполненными полями", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse(mediaItem()));
		vi.stubGlobal("fetch", fetchMock);

		const media = await updateMetadata(7, {
			title: "Новое название",
			artists: ["Исполнитель"],
			album: "Альбом",
			genre: "",
			year: 2024,
			description: "",
			sourceUrl: "",
		});

		expect(fetchMock).toHaveBeenCalledOnce();
		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/metadata/7");
		expect(init.method).toBe("PUT");
		const body = JSON.parse(init.body as string) as Record<string, unknown>;
		expect(body.title).toBe("Новое название");
		expect(body.artists).toEqual(["Исполнитель"]);
		expect(body.album).toBe("Альбом");
		// Пустые необязательные поля не отправляются, source_url — всегда.
		expect(body).not.toHaveProperty("genre");
		expect(body).not.toHaveProperty("description");
		expect(body.source_url).toBe("");
		expect(body.year).toBe(2024);
		expect(media.title).toBe("Новое название");
	});

	it("не отправляет source_url без изменений", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse(mediaItem()));
		vi.stubGlobal("fetch", fetchMock);

		await updateMetadata(7, {
			title: "Новое название",
			artists: [],
		});

		const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		const body = JSON.parse(init.body as string) as Record<string, unknown>;
		expect(body).not.toHaveProperty("source_url");
	});

	it("пробрасывает сообщение сервера", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ error: "Invalid year" }, 400));
		vi.stubGlobal("fetch", fetchMock);

		await expect(
			updateMetadata(7, { title: "Название", artists: [] }),
		).rejects.toThrow("Invalid year");
	});
});

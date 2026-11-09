import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError } from "./client";
import {
	addToCollection,
	bulkAddCollectionItems,
	bulkMoveCollectionItems,
	bulkRemoveCollectionItems,
	createCollection,
	deleteCollection,
	fetchCollectionItems,
	fetchCollectionStats,
	fetchCollections,
	moveCollection,
	moveCollectionItem,
	removeFromCollection,
	renameCollection,
} from "./collections";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

function collectionBody(id: number, parentId: number | null = null) {
	return {
		id,
		user_id: 1,
		name: `Collection ${id}`,
		type: "video",
		parent_id: parentId,
		created_at: "2026-01-01T00:00:00Z",
		updated_at: "2026-01-01T00:00:00Z",
	};
}

function mediaItem(id: number) {
	return {
		id,
		title: `Film ${id}`,
		filename: "",
		year: 2024,
		description: "",
		type: "video",
		artists: [],
		album: "",
		genre: "",
		duration: 3600,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: "",
		view_count: 1,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "",
	};
}

function firstCall(fetchMock: ReturnType<typeof vi.fn>): [string, RequestInit] {
	return fetchMock.mock.calls[0] as [string, RequestInit];
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("fetchCollections", () => {
	it("парсит дерево коллекций", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(
				jsonResponse([collectionBody(1), collectionBody(2, 1)]),
			);
		vi.stubGlobal("fetch", fetchMock);

		const collections = await fetchCollections();

		expect(collections.map((item) => item.id)).toEqual([1, 2]);
		expect(collections[1]?.parent_id).toBe(1);
		expect(firstCall(fetchMock)[0]).toBe("/api/collections");
	});
});

describe("fetchCollectionItems", () => {
	it("парсит вложенные медиа", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse([mediaItem(7), mediaItem(8)]));
		vi.stubGlobal("fetch", fetchMock);

		const items = await fetchCollectionItems(3);

		expect(items.map((item) => item.id)).toEqual([7, 8]);
		expect(firstCall(fetchMock)[0]).toBe("/api/collections/3/items");
	});

	it("пробрасывает 404 для чужой или удалённой коллекции", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(jsonResponse({ error: "not found" }, 404)),
		);

		const request = fetchCollectionItems(99);

		await expect(request).rejects.toBeInstanceOf(ApiError);
		await expect(request).rejects.toMatchObject({
			status: 404,
			message: "not found",
		});
	});
});

describe("fetchCollectionStats", () => {
	it("парсит подколлекции и элементы", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ subcollections: 2, items: 9 }));
		vi.stubGlobal("fetch", fetchMock);

		await expect(fetchCollectionStats(4)).resolves.toEqual({
			subcollections: 2,
			items: 9,
		});
		expect(firstCall(fetchMock)[0]).toBe("/api/collections/4/stats");
	});
});

describe("createCollection", () => {
	it("отправляет имя и тип", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(collectionBody(5), 201));
		vi.stubGlobal("fetch", fetchMock);

		await createCollection("Сезон 1", "video");

		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections");
		expect(init.method).toBe("POST");
		expect(JSON.parse(init.body as string)).toEqual({
			name: "Сезон 1",
			type: "video",
		});
	});
});

describe("renameCollection", () => {
	it("отправляет новое имя", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse(collectionBody(5)));
		vi.stubGlobal("fetch", fetchMock);

		await renameCollection(5, "Новое имя");

		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/5");
		expect(init.method).toBe("PUT");
		expect(JSON.parse(init.body as string)).toEqual({ name: "Новое имя" });
	});
});

describe("deleteCollection", () => {
	it("удаляет коллекцию", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ message: "Collection deleted" }));
		vi.stubGlobal("fetch", fetchMock);

		await deleteCollection(5);

		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/5");
		expect(init.method).toBe("DELETE");
	});
});

describe("addToCollection", () => {
	it("отправляет media_id", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ id: 1, media_id: 7 }, 201));
		vi.stubGlobal("fetch", fetchMock);

		await addToCollection(3, 7);

		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/3/items");
		expect(init.method).toBe("POST");
		expect(JSON.parse(init.body as string)).toEqual({ media_id: 7 });
	});

	it("пробрасывает 409 дубликата", async () => {
		vi.stubGlobal(
			"fetch",
			vi
				.fn()
				.mockResolvedValue(
					jsonResponse({ error: "Media already in collection" }, 409),
				),
		);

		await expect(addToCollection(3, 7)).rejects.toMatchObject({
			status: 409,
			message: "Media already in collection",
		});
	});
});

describe("bulkAddCollectionItems", () => {
	it("отправляет media_ids и разбирает bulk-ответ", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(
				jsonResponse({ added: [1], moved: null, removed: null, skipped: [2] }),
			);
		vi.stubGlobal("fetch", fetchMock);

		await expect(bulkAddCollectionItems(3, [1, 2])).resolves.toEqual({
			added: [1],
			moved: null,
			removed: null,
			skipped: [2],
		});
		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/3/items/bulk");
		expect(init.method).toBe("POST");
		expect(JSON.parse(init.body as string)).toEqual({
			media_ids: [1, 2],
		});
	});
});

describe("moveCollectionItem", () => {
	it("отправляет media_id и to_collection_id", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ id: 3, collection_id: 2 }));
		vi.stubGlobal("fetch", fetchMock);

		await moveCollectionItem(1, 2, 7);

		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/1/items/move");
		expect(init.method).toBe("POST");
		expect(JSON.parse(init.body as string)).toEqual({
			media_id: 7,
			to_collection_id: 2,
		});
	});
});

describe("moveCollection", () => {
	it("шлёт parent_id явно, включая null для корня", async () => {
		const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ id: 2 }));
		vi.stubGlobal("fetch", fetchMock);

		await moveCollection(2, null);

		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/2");
		expect(init.method).toBe("PUT");
		// Отсутствие ключа бэкенд читает как «не трогать».
		expect(JSON.parse(init.body as string)).toEqual({ parent_id: null });
	});
});

describe("removeFromCollection", () => {
	it("удаляет элемент по mediaId", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ message: "Item removed" }));
		vi.stubGlobal("fetch", fetchMock);

		await removeFromCollection(3, 7);

		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/3/items/7");
		expect(init.method).toBe("DELETE");
	});
});

describe("bulkRemoveCollectionItems", () => {
	it("разбирает bulk-ответ с удалёнными и пропущенными", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ removed: [1, 2], skipped: [3] }));
		vi.stubGlobal("fetch", fetchMock);

		await expect(bulkRemoveCollectionItems(3, [1, 2, 3])).resolves.toEqual({
			removed: [1, 2],
			skipped: [3],
		});
		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/3/items");
		expect(init.method).toBe("DELETE");
		expect(JSON.parse(init.body as string)).toEqual({
			media_ids: [1, 2, 3],
		});
	});

	it("принимает null вместо отсутствующих массивов", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(
				jsonResponse({
					added: null,
					moved: null,
					removed: [1, 2],
					skipped: [3],
				}),
			),
		);

		await expect(bulkRemoveCollectionItems(3, [1, 2, 3])).resolves.toEqual({
			added: null,
			moved: null,
			removed: [1, 2],
			skipped: [3],
		});
	});
});

describe("bulkMoveCollectionItems", () => {
	it("разбирает частичный перенос: moved и skipped", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ moved: [10, 11], skipped: [12] }));
		vi.stubGlobal("fetch", fetchMock);

		await expect(
			bulkMoveCollectionItems(3, {
				mediaIds: [10, 11, 12],
				toCollectionId: 4,
			}),
		).resolves.toEqual({ moved: [10, 11], skipped: [12] });
		const [url, init] = firstCall(fetchMock);
		expect(url).toBe("/api/collections/3/items/move/bulk");
		expect(init.method).toBe("POST");
		expect(JSON.parse(init.body as string)).toEqual({
			media_ids: [10, 11, 12],
			to_collection_id: 4,
		});
	});

	it("принимает null для неиспользуемых массивов", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(
				jsonResponse({
					added: null,
					moved: [10, 11],
					removed: null,
					skipped: [12],
				}),
			),
		);

		await expect(
			bulkMoveCollectionItems(3, {
				mediaIds: [10, 11, 12],
				toCollectionId: 4,
			}),
		).resolves.toEqual({
			added: null,
			moved: [10, 11],
			removed: null,
			skipped: [12],
		});
	});

	it("принимает все массивы bulk-результата", async () => {
		vi.stubGlobal(
			"fetch",
			vi.fn().mockResolvedValue(
				jsonResponse({
					added: [1],
					moved: [2],
					removed: [3],
					skipped: [4],
				}),
			),
		);

		await expect(
			bulkMoveCollectionItems(3, { mediaIds: [2], toCollectionId: 4 }),
		).resolves.toEqual({
			added: [1],
			moved: [2],
			removed: [3],
			skipped: [4],
		});
	});
});

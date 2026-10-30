import { afterEach, describe, expect, it, vi } from "vitest";
import { moveCollectionItem } from "./collections";

function jsonResponse(body: unknown, status = 200): Response {
	return new Response(JSON.stringify(body), {
		status,
		headers: { "Content-Type": "application/json" },
	});
}

afterEach(() => {
	vi.unstubAllGlobals();
});

describe("moveCollectionItem", () => {
	it("отправляет POST с media_id и to_collection_id", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(jsonResponse({ id: 3, collection_id: 2 }));
		vi.stubGlobal("fetch", fetchMock);

		await moveCollectionItem(1, 2, 7);

		expect(fetchMock).toHaveBeenCalledOnce();
		const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
		expect(url).toBe("/api/collections/1/items/move");
		expect(init.method).toBe("POST");
		expect(JSON.parse(init.body as string)).toEqual({
			media_id: 7,
			to_collection_id: 2,
		});
	});

	it("пробрасывает конфликт дубликата", async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValue(
				jsonResponse({ error: "Media already in target collection" }, 409),
			);
		vi.stubGlobal("fetch", fetchMock);

		await expect(moveCollectionItem(1, 2, 7)).rejects.toThrow(
			"Media already in target collection",
		);
	});
});

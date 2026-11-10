import { ApiError, type Collection, type Media } from "@flux/shared";
import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";
import {
	invalidateTrash,
	isTrashEmpty,
	isTrashMissing,
	parseTrash,
	trashCount,
	trashErrorKey,
} from "./trash";

const CREATED_AT = "2026-01-01T00:00:00Z";
const ACTION_ERROR = "trash.actionError";

function mediaFixture(overrides: Partial<Media> = {}): Media {
	return {
		id: 1,
		title: "Видео",
		filename: "video.mp4",
		year: 2024,
		description: "",
		type: "video",
		artists: [],
		album: "",
		genre: "",
		duration: 120,
		width: 1920,
		height: 1080,
		file_size: 1000,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: CREATED_AT,
		source_url: "",
		...overrides,
	};
}

function collectionFixture(overrides: Partial<Collection> = {}): Collection {
	return {
		id: 1,
		user_id: 7,
		name: "Коллекция",
		type: "video",
		parent_id: null,
		created_at: CREATED_AT,
		updated_at: CREATED_AT,
		...overrides,
	};
}

describe("parseTrash", () => {
	it("читает коллекции и медиа из ответа /trash", () => {
		const data = parseTrash({
			collections: [collectionFixture({ id: 3 })],
			media: [mediaFixture({ id: 9 })],
		});
		expect(data.collections[0]?.id).toBe(3);
		expect(data.media[0]?.id).toBe(9);
	});

	it("null вместо artists превращается в пустой список", () => {
		const data = parseTrash({
			collections: [],
			media: [{ ...mediaFixture(), artists: null }],
		});
		expect(data.media[0]?.artists).toEqual([]);
	});

	it("ответ без массивов не считается корзиной", () => {
		expect(() => parseTrash({ media: [] })).toThrow();
		expect(() => parseTrash({ collections: [] })).toThrow();
	});
});

describe("trashCount / isTrashEmpty", () => {
	it("складывает коллекции и медиа", () => {
		const data = {
			collections: [collectionFixture(), collectionFixture({ id: 2 })],
			media: [mediaFixture()],
		};
		expect(trashCount(data)).toBe(3);
		expect(isTrashEmpty(data)).toBe(false);
	});

	it("пустая корзина даёт ноль", () => {
		const data = { collections: [], media: [] };
		expect(trashCount(data)).toBe(0);
		expect(isTrashEmpty(data)).toBe(true);
	});
});

describe("isTrashMissing", () => {
	it("404 означает устаревшую запись", () => {
		expect(isTrashMissing(new ApiError(404, "not found"))).toBe(true);
	});

	it("409 и сетевые ошибки — не 404", () => {
		expect(isTrashMissing(new ApiError(409, "conflict"))).toBe(false);
		expect(isTrashMissing(new Error("network"))).toBe(false);
		expect(isTrashMissing(null)).toBe(false);
	});
});

describe("trashErrorKey", () => {
	it("различает 404, 409 и 403", () => {
		expect(trashErrorKey(new ApiError(404, "missing"))).toBe(
			"trash.missingError",
		);
		expect(trashErrorKey(new ApiError(409, "conflict"))).toBe(
			"trash.conflictError",
		);
		expect(trashErrorKey(new ApiError(403, "forbidden"))).toBe(
			"trash.forbiddenError",
		);
	});

	it("прочие сбои уходят в общий текст", () => {
		expect(trashErrorKey(new ApiError(500, "boom"))).toBe(ACTION_ERROR);
		expect(trashErrorKey(new Error("network"))).toBe(ACTION_ERROR);
		expect(trashErrorKey(undefined)).toBe(ACTION_ERROR);
	});
});

describe("invalidateTrash", () => {
	it("сбрасывает корзину, медиатеку и зависимые подборки", () => {
		const client = new QueryClient();
		const invalidate = vi.spyOn(client, "invalidateQueries");

		invalidateTrash(client);

		const keys = invalidate.mock.calls.map((call) => call[0]?.queryKey);
		expect(keys).toEqual([
			["trash"],
			["media"],
			["collections"],
			["favorites"],
			["progress"],
		]);
	});
});

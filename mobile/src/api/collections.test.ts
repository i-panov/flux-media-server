import { ApiError } from "@flux/shared";
import { QueryClient } from "@tanstack/react-query";
import { describe, expect, it, vi } from "vitest";
import {
	invalidateAfterCollectionDelete,
	isAlreadyInCollection,
	isCollectionMissing,
} from "./collections";

describe("isAlreadyInCollection", () => {
	it("считает 409 дубликатом, а не сетевым сбоем", () => {
		expect(isAlreadyInCollection(new ApiError(409, "duplicate"))).toBe(true);
	});

	it("прочие статусы и ошибки не считает дубликатом", () => {
		expect(isAlreadyInCollection(new ApiError(500, "boom"))).toBe(false);
		expect(isAlreadyInCollection(new Error("network"))).toBe(false);
		expect(isAlreadyInCollection(null)).toBe(false);
	});
});

describe("isCollectionMissing", () => {
	it("распознаёт 404 удалённой коллекции", () => {
		expect(isCollectionMissing(new ApiError(404, "missing"))).toBe(true);
	});

	it("не путает с другими ошибками", () => {
		expect(isCollectionMissing(new ApiError(409, "duplicate"))).toBe(false);
		expect(isCollectionMissing(new Error("network"))).toBe(false);
		expect(isCollectionMissing(undefined)).toBe(false);
	});
});

describe("invalidateAfterCollectionDelete", () => {
	it("убирает кэш коллекции, список и корзину", () => {
		const client = new QueryClient();
		const remove = vi.spyOn(client, "removeQueries");
		const invalidate = vi.spyOn(client, "invalidateQueries");

		invalidateAfterCollectionDelete(client, 42);

		expect(remove).toHaveBeenCalledWith({ queryKey: ["collections", 42] });
		const keys = invalidate.mock.calls.map((call) => call[0]?.queryKey);
		expect(keys).toEqual([["collections"], ["trash"]]);
	});
});

import type { Collection } from "@flux/shared";
import { describe, expect, it } from "vitest";
import {
	clampProgress,
	continueProgressRatio,
	isRowVisible,
	rootCollections,
} from "./homeRows";

function collection(
	id: number,
	type: string,
	parentId: number | null | undefined = null,
): Collection {
	return {
		id,
		user_id: 1,
		name: `Collection ${id}`,
		type,
		parent_id: parentId,
		created_at: "",
		updated_at: "",
	};
}

describe("isRowVisible", () => {
	it("скрывает пустой, отсутствующий и null-список", () => {
		expect(isRowVisible([])).toBe(false);
		expect(isRowVisible(undefined)).toBe(false);
		expect(isRowVisible(null)).toBe(false);
	});

	it("показывает ряд с элементами", () => {
		expect(isRowVisible([1])).toBe(true);
	});
});

describe("clampProgress", () => {
	it("держит прогресс в диапазоне 0..1", () => {
		expect(clampProgress(-0.5)).toBe(0);
		expect(clampProgress(0.5)).toBe(0.5);
		expect(clampProgress(2)).toBe(1);
	});

	it("NaN и Infinity не дают пустую полосу", () => {
		expect(clampProgress(Number.NaN)).toBe(0);
		expect(clampProgress(Number.POSITIVE_INFINITY)).toBe(1);
	});
});

describe("continueProgressRatio", () => {
	it("считает долю от длительности прогресса", () => {
		expect(continueProgressRatio({ position: 30, duration: 120 })).toBe(0.25);
	});

	it("берёт duration медиа, если в прогрессе она нулевая", () => {
		expect(continueProgressRatio({ position: 15, duration: 0 }, 60)).toBe(0.25);
	});

	it("без известной длительности прогресс нулевой", () => {
		expect(continueProgressRatio({ position: 15, duration: 0 })).toBe(0);
	});

	it("не выходит за 100%", () => {
		expect(continueProgressRatio({ position: 300, duration: 120 })).toBe(1);
	});
});

describe("rootCollections", () => {
	const all = [
		collection(1, "video"),
		collection(2, "video", 1),
		collection(3, "audio"),
		collection(4, "video", 999),
	];

	it("фильтрует по типу и оставляет только корни", () => {
		expect(rootCollections(all, "video").map((item) => item.id)).toEqual([
			1, 4,
		]);
		expect(rootCollections(all, "audio").map((item) => item.id)).toEqual([3]);
	});

	it("коллекция с отсутствующим родителем считается корнем", () => {
		expect(
			rootCollections([collection(5, "video", 404)], "video"),
		).toHaveLength(1);
	});

	it("пустой список даёт пустой ряд", () => {
		expect(rootCollections([], "video")).toEqual([]);
	});
});

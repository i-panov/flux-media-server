import type { Media } from "@flux/shared";
import { describe, expect, it } from "vitest";
import { excludeMediaIds, isEmptyBecauseOfExclusions } from "./visibleMedia";

function media(id: number): Media {
	return {
		id,
		title: `Media ${id}`,
		filename: "",
		year: 0,
		description: "",
		type: "video",
		artists: [],
		album: "",
		genre: "",
		duration: 120,
		width: 0,
		height: 0,
		file_size: 0,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "",
		source_url: "",
	};
}

describe("excludeMediaIds", () => {
	it("пока избранное не загружено, список не фильтруется", () => {
		expect(excludeMediaIds([media(1), media(2)], undefined)).toEqual([
			media(1),
			media(2),
		]);
	});

	it("пустой набор избранного ничего не скрывает", () => {
		expect(excludeMediaIds([media(1)], new Set())).toEqual([media(1)]);
	});

	it("скрывает медиа из загруженного набора избранного", () => {
		expect(
			excludeMediaIds([media(1), media(2), media(3)], new Set([2])),
		).toEqual([media(1), media(3)]);
	});

	it("все элементы могут оказаться избранными", () => {
		expect(excludeMediaIds([media(1)], new Set([1]))).toEqual([]);
	});
});

// biome-ignore lint/security/noSecrets: имя тестируемой функции, не секрет.
describe("isEmptyBecauseOfExclusions", () => {
	it("распознаёт список, целиком скрытый избранным", () => {
		expect(
			isEmptyBecauseOfExclusions({
				searching: false,
				allCount: 2,
				visibleCount: 0,
				excludedCount: 2,
			}),
		).toBe(true);
	});

	it("не считает пустым реально пустую библиотеку", () => {
		expect(
			isEmptyBecauseOfExclusions({
				searching: false,
				allCount: 0,
				visibleCount: 0,
				excludedCount: 0,
			}),
		).toBe(false);
	});

	it("при поиске избранное не исключается и состояние не favorites", () => {
		expect(
			isEmptyBecauseOfExclusions({
				searching: true,
				allCount: 2,
				visibleCount: 0,
				excludedCount: 2,
			}),
		).toBe(false);
	});

	it("если видимые элементы есть, это обычный список", () => {
		expect(
			isEmptyBecauseOfExclusions({
				searching: false,
				allCount: 2,
				visibleCount: 1,
				excludedCount: 1,
			}),
		).toBe(false);
	});
});

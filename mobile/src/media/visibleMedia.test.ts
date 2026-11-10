import type { Media } from "@flux/shared";
import { describe, expect, it } from "vitest";
import { excludeMediaIds } from "./visibleMedia";

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

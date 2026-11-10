import { describe, expect, it } from "vitest";
import {
	audioFavoritesQueryKey,
	favoriteIds,
	videoFavoritesQueryKey,
} from "./favorites";

describe("favoriteIds", () => {
	it("собирает id избранных медиа в Set", () => {
		expect(favoriteIds([{ id: 5 }, { id: 9 }])).toEqual(new Set([5, 9]));
	});

	it("пустой список даёт пустой Set", () => {
		expect(favoriteIds([]).size).toBe(0);
	});

	it("дубликаты не раздувают Set", () => {
		expect(favoriteIds([{ id: 3 }, { id: 3 }])).toEqual(new Set([3]));
	});
});

describe("favoritesQueryKey", () => {
	it("разделяет избранное видео и аудио", () => {
		expect(videoFavoritesQueryKey).toEqual(["favorites", "video", "all"]);
		expect(audioFavoritesQueryKey).toEqual(["favorites", "audio", "all"]);
	});
});

import type { Media } from "@flux/shared";
import { describe, expect, it } from "vitest";
import {
	artistFavoritesQueryKey,
	audioFavoritesQueryKey,
	favoriteIds,
	nextFavoriteArtistIds,
	nextFavoriteMedia,
	videoFavoritesQueryKey,
} from "./favorites";

function media(id: number, title = `Media ${id}`): Media {
	return {
		id,
		title,
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

	it("избранные артисты получают собственный ключ", () => {
		expect(artistFavoritesQueryKey).toEqual(["favorites", "artists", "all"]);
	});
});

describe("nextFavoriteMedia", () => {
	it("добавляет медиа в начало списка", () => {
		const added = media(7);
		expect(
			nextFavoriteMedia([media(1), media(2)], {
				mediaId: 7,
				favorite: false,
				media: added,
			}),
		).toEqual([added, media(1), media(2)]);
	});

	it("удаляет медиа из списка", () => {
		expect(
			nextFavoriteMedia([media(1), media(2)], {
				mediaId: 2,
				favorite: true,
			}),
		).toEqual([media(1)]);
	});

	it("не дублирует запись при повторном добавлении", () => {
		const added = media(1);
		expect(
			nextFavoriteMedia([media(1), media(2)], {
				mediaId: 1,
				favorite: false,
				media: added,
			}),
		).toEqual([added, media(2)]);
	});

	it("без media добавление не меняет список", () => {
		expect(
			nextFavoriteMedia([media(1)], { mediaId: 2, favorite: false }),
		).toEqual([media(1)]);
	});
});

describe("nextFavoriteArtistIds", () => {
	it("добавляет и удаляет id, не мутируя исходный Set", () => {
		const source = new Set([1]);
		const added = nextFavoriteArtistIds(source, 2, false);
		expect(added).toEqual(new Set([1, 2]));
		expect(source).toEqual(new Set([1]));

		expect(nextFavoriteArtistIds(added, 1, true)).toEqual(new Set([2]));
	});
});

import { describe, expect, it } from "vitest";
import { artistsQueryKey, normalizeArtists } from "./metadata";

describe("normalizeArtists", () => {
	it("читает items и приводит поля к контракту", () => {
		expect(
			normalizeArtists({
				items: [
					{ id: 2, name: "Beta", has_cover: true, updated_at: "2026-01-02" },
					{ id: 1, name: "Alpha" },
				],
			}),
		).toEqual([
			{ id: 1, name: "Alpha", has_cover: false, updated_at: "" },
			{ id: 2, name: "Beta", has_cover: true, updated_at: "2026-01-02" },
		]);
	});

	it("принимает массив без обёртки и сортирует по имени", () => {
		expect(
			normalizeArtists([
				{ id: 1, name: "Zulu" },
				{ id: 2, name: "Alpha" },
			]).map((artist) => artist.name),
		).toEqual(["Alpha", "Zulu"]);
	});

	it("убирает дубликаты по имени и невалидные записи", () => {
		const artists = normalizeArtists({
			items: [
				{ id: 1, name: "Alpha" },
				{ id: 2, name: "Alpha" },
				{ id: 0, name: "Zero" },
				{ id: 3, name: "" },
				null,
				{ id: 4, name: "Beta", unknown: true },
			],
		});
		expect(artists.map((artist) => artist.id)).toEqual([1, 4]);
	});

	it("бросает ошибку на неожиданный ответ", () => {
		expect(() => normalizeArtists(null)).toThrow("Unexpected artists response");
		expect(() => normalizeArtists({ items: "nope" })).toThrow(
			"Unexpected artists response",
		);
	});
});

describe("artistsQueryKey", () => {
	it("совпадает с ключом web", () => {
		expect(artistsQueryKey).toEqual(["artists"]);
	});
});

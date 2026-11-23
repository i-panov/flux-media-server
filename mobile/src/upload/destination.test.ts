import type { Media } from "@flux/shared";
import { describe, expect, it } from "vitest";
import { assignmentFor } from "./destination";

function media(id: number, type: string): Media {
	return {
		id,
		title: `Media ${id}`,
		filename: "",
		year: 2026,
		description: "",
		type,
		artists: [],
		album: "",
		genre: "",
		duration: 1,
		width: 0,
		height: 0,
		file_size: 1,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "",
	};
}

describe("assignmentFor", () => {
	it("сольное видео не назначается", () => {
		expect(
			assignmentFor(
				{ kind: "standalone", workID: null, seasonID: null, franchiseID: null },
				media(5, "video"),
			),
		).toBeNull();
	});

	it("неполное назначение не отправляется", () => {
		expect(
			assignmentFor(
				{ kind: "series", workID: 1, seasonID: null, franchiseID: null },
				media(5, "video"),
			),
		).toBeNull();
		expect(
			assignmentFor(
				{ kind: "franchise", workID: null, seasonID: null, franchiseID: null },
				media(5, "video"),
			),
		).toBeNull();
	});

	it("строит назначение для сериала, серии фильмов и франшизы", () => {
		expect(
			assignmentFor(
				{ kind: "series", workID: 1, seasonID: 2, franchiseID: null },
				media(5, "video"),
			),
		).toEqual({ kind: "episode", seasonID: 2, mediaID: 5 });
		expect(
			assignmentFor(
				{ kind: "film_series", workID: 3, seasonID: null, franchiseID: null },
				media(6, "video"),
			),
		).toEqual({ kind: "film", workID: 3, mediaID: 6 });
		expect(
			assignmentFor(
				{ kind: "franchise", workID: null, seasonID: null, franchiseID: 4 },
				media(7, "video"),
			),
		).toEqual({ kind: "franchise", franchiseID: 4, mediaID: 7 });
	});

	it("аудио и картинки не попадают в каталог", () => {
		expect(
			assignmentFor(
				{ kind: "series", workID: 1, seasonID: 2, franchiseID: null },
				media(8, "audio"),
			),
		).toBeNull();
	});
});

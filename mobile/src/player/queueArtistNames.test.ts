import type { AudioQueueState, Media } from "@flux/shared";
import { describe, expect, it } from "vitest";
import { applyArtistNames } from "./queueArtistNames";

const OLD_NAME = "Старое имя";
const NEW_NAME = "Новое имя";
const SECOND_NAME = "Второй";

function media(id: number, artists: Media["artists"]): Media {
	return {
		id,
		title: `Трек ${id}`,
		filename: `${id}.mp3`,
		year: 2026,
		description: "",
		type: "audio",
		artists,
		album: "",
		genre: "",
		duration: 120,
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

function queue(): AudioQueueState {
	return {
		items: [
			media(1, [{ id: 7, name: OLD_NAME, has_cover: false, updated_at: "" }]),
			media(2, [
				{ id: 7, name: OLD_NAME, has_cover: false, updated_at: "" },
				{ id: 9, name: SECOND_NAME, has_cover: false, updated_at: "" },
			]),
		],
		index: 1,
	};
}

describe("applyArtistNames", () => {
	it("обновляет имена во всех треках по artist_id и сохраняет индекс", () => {
		const state = queue();
		const next = applyArtistNames(state, new Map([[7, NEW_NAME]]));

		expect(next).not.toBe(state);
		expect(next.index).toBe(1);
		expect(next.items[0]?.artists[0]?.name).toBe(NEW_NAME);
		expect(next.items[1]?.artists[0]?.name).toBe(NEW_NAME);
		expect(next.items[1]?.artists[1]?.name).toBe(SECOND_NAME);
	});

	it("не трогает треки без совпадающего artist_id", () => {
		const state = queue();
		const next = applyArtistNames(state, new Map([[99, "Чужой"]]));
		expect(next).toBe(state);
	});

	it("возвращает тот же объект, если имя не изменилось", () => {
		const state = queue();
		const next = applyArtistNames(state, new Map([[7, OLD_NAME]]));
		expect(next).toBe(state);
	});
});

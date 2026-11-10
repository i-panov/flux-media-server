import {
	type AudioQueueState,
	emptyQueue,
	type Media,
	movePlayedIndices,
	moveTrack,
	parseSyncedLyrics,
	shiftPlayedIndices,
	syncedLyricIndex,
} from "@flux/shared";
import { describe, expect, it } from "vitest";

function media(id: number): Media {
	return {
		id,
		title: `Свой трек ${id}`,
		filename: `${id}.mp3`,
		year: 2026,
		description: "",
		type: "audio",
		artists: [],
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

function queue(ids: number[], index: number): AudioQueueState {
	return { items: ids.map(media), index };
}

function ids(state: AudioQueueState): number[] {
	return state.items.map((item) => item.id);
}

describe("shared audioQueue в mobile", () => {
	it("перестановка текущего трека переносит индекс", () => {
		const state = moveTrack(queue([1, 2, 3], 1), 2, 0);
		expect(ids(state)).toEqual([3, 1, 2]);
		expect(state.index).toBe(2);
	});

	it("перестановка чужого трека не двигает текущий индекс", () => {
		const state = moveTrack(queue([1, 2, 3], 0), 2, 1);
		expect(ids(state)).toEqual([1, 3, 2]);
		expect(state.index).toBe(0);
	});

	it("перестановка за границы очереди ничего не меняет", () => {
		const state = queue([1, 2], 0);
		expect(moveTrack(state, 0, 4)).toBe(state);
	});

	it("история shuffle переезжает вместе с треком", () => {
		expect([...movePlayedIndices(new Set([1, 2]), 2, 0)].sort()).toEqual([
			0, 2,
		]);
	});

	it("удаление трека сдвигает played-индексы", () => {
		expect(shiftPlayedIndices(new Set([0, 1, 2]), 1)).toEqual(new Set([0, 1]));
		expect(shiftPlayedIndices(new Set([0, 2]), 0)).toEqual(new Set([1]));
	});

	it("очередь без треков остаётся пустой", () => {
		expect(emptyQueue).toEqual({ items: [], index: 0 });
	});
});

describe("shared lyricsSync в mobile", () => {
	it("разбирает таймкоды и подсвечивает последнюю строку", () => {
		// biome-ignore lint/security/noSecrets: LRC-фикстура, а не секрет.
		const lines = parseSyncedLyrics("[00:01.50] Первая\n[00:03] Вторая");
		expect(lines).toEqual([
			{ time: 1.5, text: "Первая" },
			{ time: 3, text: "Вторая" },
		]);
		expect(syncedLyricIndex(lines, 2)).toBe(0);
		expect(syncedLyricIndex(lines, 4)).toBe(1);
	});
});

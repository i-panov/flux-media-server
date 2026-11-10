import type { AudioQueueState, Media, RepeatMode } from "@flux/shared";
import { describe, expect, it } from "vitest";
import {
	AUDIO_QUEUE_SCHEMA_VERSION,
	parseAudioQueue,
	serializeAudioQueue,
} from "./queuePersistence";

function media(id: number): Media {
	return {
		id,
		title: `Трек ${id}`,
		filename: `${id}.mp3`,
		year: 2026,
		description: "",
		type: "audio",
		artists: [{ id: 7, name: "Исполнитель", has_cover: false, updated_at: "" }],
		album: "Альбом",
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

function payload(overrides: Record<string, unknown>): string {
	return JSON.stringify({
		version: AUDIO_QUEUE_SCHEMA_VERSION,
		items: [media(1), media(2)],
		index: 0,
		played: [0],
		shuffle: false,
		repeat: "off" satisfies RepeatMode,
		...overrides,
	});
}

describe("audio queue persistence", () => {
	it("сериализует и восстанавливает очередь с режимами", () => {
		const state: AudioQueueState = queue([1, 2, 3], 1);
		const raw = serializeAudioQueue({
			queue: state,
			played: new Set([0, 2]),
			shuffle: true,
			repeat: "one",
		});

		const restored = parseAudioQueue(raw);

		expect(restored).not.toBeNull();
		expect(restored?.queue.items.map((item) => item.id)).toEqual([1, 2, 3]);
		expect(restored?.queue.index).toBe(1);
		expect([...(restored?.played ?? [])].sort()).toEqual([0, 2]);
		expect(restored?.shuffle).toBe(true);
		expect(restored?.repeat).toBe("one");
	});

	it("обрезает индекс и выбрасывает невалидную историю", () => {
		const restored = parseAudioQueue(
			payload({ index: 9, played: [-1, 1, 5, "x"] }),
		);

		expect(restored?.queue.index).toBe(1);
		expect([...(restored?.played ?? [])]).toEqual([1]);
	});

	it("пустая история начинается с текущего трека", () => {
		const restored = parseAudioQueue(payload({ index: 1, played: [] }));
		expect([...(restored?.played ?? [])]).toEqual([1]);
	});

	it("битый JSON не роняет восстановление", () => {
		expect(parseAudioQueue("{oops")).toBeNull();
		expect(parseAudioQueue(null)).toBeNull();
		expect(parseAudioQueue("")).toBeNull();
	});

	it("чужая версия схемы игнорируется", () => {
		expect(parseAudioQueue(payload({ version: 99 }))).toBeNull();
	});

	it("пустая очередь и битый Media не восстанавливаются", () => {
		expect(parseAudioQueue(payload({ items: [] }))).toBeNull();
		expect(parseAudioQueue(payload({ items: [{ id: 1 }] }))).toBeNull();
	});

	it("неизвестные режимы откатываются к безопасным дефолтам", () => {
		const restored = parseAudioQueue(
			payload({ repeat: "sideways", shuffle: "yes" }),
		);
		expect(restored?.repeat).toBe("off");
		expect(restored?.shuffle).toBe(false);
	});
});

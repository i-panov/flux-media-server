import { beforeEach, describe, expect, it } from "vitest";
import type { Media } from "../../core/media";
import {
	clearPersistedQueue,
	loadPersistedQueue,
	loadPersistedSettings,
	QUEUE_STORAGE_KEY,
	SETTINGS_STORAGE_KEY,
	savePersistedQueue,
	savePersistedSettings,
} from "./playerPersistence";

function media(id: number): Media {
	return {
		id,
		title: `Трек ${id}`,
		filename: `${id}.mp3`,
		year: 2024,
		description: "",
		type: "audio",
		artists: [],
		album: "",
		genre: "",
		duration: 180,
		width: 0,
		height: 0,
		file_size: 1,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
	};
}

beforeEach(() => {
	localStorage.clear();
});

describe("playerPersistence", () => {
	it("читает очередь и настройки из разных ключей", () => {
		savePersistedQueue(
			{ items: [media(1), media(2)], index: 1 },
			new Set([0, 1]),
		);
		savePersistedSettings({ volume: 0.5, shuffle: true, repeat: "all" });

		const restored = loadPersistedQueue();
		expect(restored?.queue.items.map((item) => item.id)).toEqual([1, 2]);
		expect(restored?.queue.index).toBe(1);
		expect(restored?.played).toEqual(new Set([0, 1]));
		const settings = loadPersistedSettings();
		expect(settings.volume).toBe(0.5);
		expect(settings.shuffle).toBe(true);
		expect(settings.repeat).toBe("all");
	});

	it("настройки пишутся без очереди", () => {
		savePersistedSettings({ volume: 0.3, shuffle: false, repeat: "off" });
		expect(localStorage.getItem(QUEUE_STORAGE_KEY)).toBeNull();
		expect(localStorage.getItem(SETTINGS_STORAGE_KEY)).not.toBeNull();
	});

	it("настройки переживают пустую и битую очередь", () => {
		savePersistedSettings({ volume: 0.3, shuffle: true, repeat: "one" });
		expect(loadPersistedQueue()).toBeNull();
		expect(loadPersistedSettings()).toEqual({
			volume: 0.3,
			shuffle: true,
			repeat: "one",
		});

		localStorage.setItem(QUEUE_STORAGE_KEY, "not json");
		expect(loadPersistedQueue()).toBeNull();
		expect(loadPersistedSettings().volume).toBe(0.3);
	});

	it("битая очередь даёт null, битые настройки — дефолты", () => {
		localStorage.setItem(QUEUE_STORAGE_KEY, "not json");
		expect(loadPersistedQueue()).toBeNull();
		expect(loadPersistedSettings()).toEqual({
			volume: 1,
			shuffle: false,
			repeat: "off",
		});

		localStorage.clear();
		savePersistedQueue({ items: [media(1)], index: 5 }, new Set([9]));
		localStorage.setItem(SETTINGS_STORAGE_KEY, "not json");
		const restored = loadPersistedQueue();
		expect(restored?.queue.index).toBe(0);
		expect(restored?.played).toEqual(new Set([0]));
		expect(loadPersistedSettings().volume).toBe(1);
	});

	it("clear стирает только очередь, настройки остаются", () => {
		savePersistedQueue({ items: [media(1)], index: 0 }, new Set([0]));
		savePersistedSettings({ volume: 0.5, shuffle: true, repeat: "all" });
		clearPersistedQueue();
		expect(loadPersistedQueue()).toBeNull();
		expect(loadPersistedSettings()).toEqual({
			volume: 0.5,
			shuffle: true,
			repeat: "all",
		});
	});
});

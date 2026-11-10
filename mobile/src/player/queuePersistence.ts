import {
	type AudioQueueState,
	type Media,
	mediaSchema,
	type RepeatMode,
} from "@flux/shared";

// Очередь аудиоплеера переживает рестарт приложения. Храним полный Media:
// он нужен мини-бару до открытия полного плеера и до запроса деталей.
// Пишем и читаем только через JSON-снимок, поэтому восстановление можно
// проверить в Node без AsyncStorage.
export const AUDIO_QUEUE_STORAGE_KEY = "flux.audio.queue";
export const AUDIO_QUEUE_SCHEMA_VERSION = 1;

export interface AudioQueueSnapshot {
	queue: AudioQueueState;
	played: ReadonlySet<number>;
	shuffle: boolean;
	repeat: RepeatMode;
}

export interface RestoredAudioQueue {
	queue: AudioQueueState;
	played: Set<number>;
	shuffle: boolean;
	repeat: RepeatMode;
}

interface SerializedAudioQueue {
	version: number;
	items: Media[];
	index: number;
	played: number[];
	shuffle: boolean;
	repeat: RepeatMode;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseItems(value: unknown): Media[] | null {
	if (!Array.isArray(value) || value.length === 0) {
		return null;
	}
	const items: Media[] = [];
	for (const raw of value) {
		const parsed = mediaSchema.safeParse(raw);
		if (!parsed.success) {
			return null;
		}
		items.push(parsed.data);
	}
	return items;
}

function clampIndex(value: unknown, length: number): number {
	if (typeof value !== "number" || !Number.isInteger(value)) {
		return 0;
	}
	return Math.min(Math.max(value, 0), length - 1);
}

function parsePlayed(
	value: unknown,
	length: number,
	index: number,
): Set<number> {
	if (!Array.isArray(value)) {
		return new Set([index]);
	}
	const played = new Set<number>();
	for (const entry of value) {
		if (typeof entry === "number" && Number.isInteger(entry)) {
			if (entry >= 0 && entry < length) {
				played.add(entry);
			}
		}
	}
	return played.size === 0 ? new Set([index]) : played;
}

function parseRepeat(value: unknown): RepeatMode {
	switch (value) {
		case "all":
		case "one":
			return value;
		default:
			return "off";
	}
}

export function serializeAudioQueue(snapshot: AudioQueueSnapshot): string {
	const payload: SerializedAudioQueue = {
		version: AUDIO_QUEUE_SCHEMA_VERSION,
		items: snapshot.queue.items,
		index: snapshot.queue.index,
		played: [...snapshot.played].sort((left, right) => left - right),
		shuffle: snapshot.shuffle,
		repeat: snapshot.repeat,
	};
	return JSON.stringify(payload);
}

// Битый JSON, несовпавшая версия, пустая очередь или невалидный Media —
// всё это null: лучше начать с пустого плеера, чем упасть на старте.
export function parseAudioQueue(
	raw: string | null | undefined,
): RestoredAudioQueue | null {
	if (raw === null || raw === undefined || raw === "") {
		return null;
	}
	let data: unknown;
	try {
		data = JSON.parse(raw) as unknown;
	} catch {
		return null;
	}
	if (!isRecord(data) || data.version !== AUDIO_QUEUE_SCHEMA_VERSION) {
		return null;
	}
	const items = parseItems(data.items);
	if (items === null) {
		return null;
	}
	const index = clampIndex(data.index, items.length);
	return {
		queue: { items, index },
		played: parsePlayed(data.played, items.length, index),
		shuffle: data.shuffle === true,
		repeat: parseRepeat(data.repeat),
	};
}

import { z } from "zod";
import { mediaSchema } from "../../core/media";
import type { AudioQueueState, RepeatMode } from "./audioQueue";

// Очередь переживает перезагрузку страницы: треки, позиция в очереди,
// история shuffle, громкость и режимы хранятся локально. Текущее время
// не храним — его подтянет useMediaProgress с сервера при старте трека.
//
// Два ключа, а не один: слайдер громкости пишет на каждый тик, и нет
// причин при этом сериализовать всю очередь заново. Настройки живут
// отдельно от очереди: громкость и режимы — предпочтения, они
// восстанавливаются, даже если очереди нет, и переживают её очистку.
export const QUEUE_STORAGE_KEY = "flux.audio-player.queue.v1";
export const SETTINGS_STORAGE_KEY = "flux.audio-player.settings.v1";

const queueSchema = z.object({
	items: z.array(mediaSchema),
	index: z.number(),
	played: z.array(z.number()),
});

const settingsSchema = z.object({
	volume: z.number(),
	shuffle: z.boolean(),
	repeat: z.enum(["off", "all", "one"]),
});

export interface PersistedQueue {
	queue: AudioQueueState;
	played: Set<number>;
}

export interface PersistedSettings {
	volume: number;
	shuffle: boolean;
	repeat: RepeatMode;
}

function clampIndex(index: number, length: number): number {
	if (!Number.isInteger(index)) {
		return 0;
	}
	return Math.min(Math.max(index, 0), length - 1);
}

function clampPlayed(
	played: number[],
	length: number,
	index: number,
): Set<number> {
	const valid = played.filter(
		(item) => Number.isInteger(item) && item >= 0 && item < length,
	);
	if (valid.length === 0) {
		return new Set([index]);
	}
	return new Set(valid);
}

function readKey<T>(key: string, schema: z.ZodType<T>): T | null {
	try {
		const raw = localStorage.getItem(key);
		if (raw === null) {
			return null;
		}
		return schema.parse(JSON.parse(raw) as unknown);
	} catch {
		// Битый JSON или чужой формат: считаем, что значения нет.
		return null;
	}
}

function writeKey(key: string, value: unknown): void {
	try {
		localStorage.setItem(key, JSON.stringify(value));
	} catch {
		// Приватный режим и переполнение: очередь просто не переживёт
		// перезагрузку, воспроизведение продолжается как обычно.
	}
}

export function loadPersistedQueue(): PersistedQueue | null {
	const parsed = readKey(QUEUE_STORAGE_KEY, queueSchema);
	if (parsed === null || parsed.items.length === 0) {
		return null;
	}
	const index = clampIndex(parsed.index, parsed.items.length);
	return {
		queue: { items: parsed.items, index },
		played: clampPlayed(parsed.played, parsed.items.length, index),
	};
}

export function loadPersistedSettings(): PersistedSettings {
	const parsed = readKey(SETTINGS_STORAGE_KEY, settingsSchema);
	if (parsed === null) {
		return { volume: 1, shuffle: false, repeat: "off" };
	}
	return {
		volume: Math.min(Math.max(parsed.volume, 0), 1),
		shuffle: parsed.shuffle,
		repeat: parsed.repeat,
	};
}

export function savePersistedQueue(
	queue: AudioQueueState,
	played: ReadonlySet<number>,
): void {
	writeKey(QUEUE_STORAGE_KEY, {
		items: queue.items,
		index: queue.index,
		played: [...played],
	});
}

export function savePersistedSettings(state: {
	volume: number;
	shuffle: boolean;
	repeat: RepeatMode;
}): void {
	writeKey(SETTINGS_STORAGE_KEY, state);
}

// Очистка плеера сносит только очередь: громкость и режимы —
// предпочтения, а не часть сессии прослушивания.
export function clearPersistedQueue(): void {
	try {
		localStorage.removeItem(QUEUE_STORAGE_KEY);
	} catch {
		// Нечего очищать или хранилище недоступно — молча пропускаем.
	}
}

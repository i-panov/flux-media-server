import { z } from "zod";
import { type Media, type MediaKind, mediaSchema } from "../core/media";
import { ApiError, apiFetch } from "./client";

export const progressSchema = z.object({
	id: z.number(),
	user_id: z.number(),
	media_id: z.number(),
	position: z.number(),
	duration: z.number(),
	completed: z.boolean(),
	updated_at: z.string(),
});

export type Progress = z.infer<typeof progressSchema>;

// Список прогресса приходит с вложенным медиа (Preload на бэкенде):
// иначе «Продолжить просмотр» делал бы запрос на каждую позицию.
export const progressEntrySchema = progressSchema.extend({
	media: mediaSchema.nullish(),
});

export type ProgressEntry = z.infer<typeof progressEntrySchema>;

// Запись с уже проверенным медиа: без него карточку не построить.
export type ContinueEntry = ProgressEntry & { media: Media };

export const progressListSchema = z.object({
	items: z.array(progressEntrySchema),
	total: z.number(),
	limit: z.number(),
	offset: z.number(),
});

export type ProgressList = z.infer<typeof progressListSchema>;

// Сколько записей тянем для блока: рядов на экране всё равно немного.
const CONTINUE_LIMIT = 20;
// Тот же порог, что в мобильном клиенте: 90% и выше — просмотрено.
const COMPLETED_RATIO = 0.9;

export async function fetchProgress(mediaId: number): Promise<Progress | null> {
	try {
		const body = await apiFetch<unknown>(`/progress/${mediaId}`);
		return progressSchema.parse(body);
	} catch (error) {
		if (error instanceof ApiError && error.status === 404) {
			return null;
		}
		throw error;
	}
}

export interface SaveProgressInput {
	mediaId: number;
	position: number;
	duration: number;
	completed: boolean;
}

export async function saveProgress({
	mediaId,
	position,
	duration,
	completed,
}: SaveProgressInput): Promise<Progress> {
	const body = await apiFetch<unknown>(`/progress/${mediaId}`, {
		method: "PUT",
		body: JSON.stringify({ position, duration, completed }),
	});
	return progressSchema.parse(body);
}

// Сброс позиции в начало (0) — это удаление серверной записи, иначе
// переоткрытие вернётся на старое место. Отсутствующую запись (404)
// считаем успехом: конечное состояние то же — прогресса нет.
export async function deleteProgress(mediaId: number): Promise<void> {
	try {
		await apiFetch<unknown>(`/progress/${mediaId}`, { method: "DELETE" });
	} catch (error) {
		if (error instanceof ApiError && error.status === 404) {
			return;
		}
		throw error;
	}
}

// Незавершённый просмотр: явный флаг снят, до 90% длительности, но что-то
// уже отсмотрено или известна длительность.
export function isUnfinishedProgress(entry: ProgressEntry): boolean {
	if (entry.completed) {
		return false;
	}
	if (
		entry.duration > 0 &&
		entry.position >= entry.duration * COMPLETED_RATIO
	) {
		return false;
	}
	return entry.duration > 0 || entry.position > 0;
}

export async function fetchContinueWatching(
	kind: MediaKind,
): Promise<ContinueEntry[]> {
	const params = new URLSearchParams({
		type: kind,
		limit: String(CONTINUE_LIMIT),
		offset: "0",
	});
	const body = await apiFetch<unknown>(`/progress?${params.toString()}`);
	const parsed = progressListSchema.parse(body);
	// Сервер фильтрует по типу, иначе более свежие записи другого типа
	// вытесняли бы весь блок. Повторная проверка на клиенте нужна старым
	// бэкендам, которые параметр type ещё не знают, и записям без медиа.
	return parsed.items.filter(
		(entry): entry is ContinueEntry =>
			entry.media !== null &&
			entry.media !== undefined &&
			entry.media.type === kind &&
			isUnfinishedProgress(entry),
	);
}

// Последний недослушанный трек для seeded-мини-плеера: свежих записей
// может быть несколько, а завершённая (дослушанная до конца) — самой
// новой, поэтому берём страницу и выбираем первую незавершённую.
// Проверку сессии и проглатывание ошибок оставляет вызывающий: вебу
// нельзя ходить в сеть без сессии, а mobile решает это сам.
export async function fetchLatestUnfinishedAudio(): Promise<Media | null> {
	const entries = await fetchContinueWatching("audio");
	return entries[0]?.media ?? null;
}

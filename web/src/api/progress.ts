import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { type Media, type MediaKind, mediaSchema } from "../core/media";
import { queryClient } from "../queryClient";
import type { AuthUser } from "./auth";
import { ApiError, apiFetch } from "./client";

const progressSchema = z.object({
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
const progressEntrySchema = progressSchema.extend({
	media: mediaSchema.nullish(),
});

type ProgressEntry = z.infer<typeof progressEntrySchema>;

// Запись с уже проверенным медиа: без него карточку не построить.
export type ContinueEntry = ProgressEntry & { media: Media };

const progressListSchema = z.object({
	items: z.array(progressEntrySchema),
	total: z.number(),
	limit: z.number(),
	offset: z.number(),
});

// Сколько записей тянем для блока: рядов на экране всё равно немного.
const CONTINUE_LIMIT = 20;
// Тот же порог, что в мобильном клиенте: 90% и выше — просмотрено.
const COMPLETED_RATIO = 0.9;

async function fetchProgress(mediaId: number): Promise<Progress | null> {
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

async function saveProgress({
	mediaId,
	position,
	duration,
	completed,
}: {
	mediaId: number;
	position: number;
	duration: number;
	completed: boolean;
}): Promise<Progress> {
	const body = await apiFetch<unknown>(`/progress/${mediaId}`, {
		method: "PUT",
		body: JSON.stringify({ position, duration, completed }),
	});
	return progressSchema.parse(body);
}

export function useProgress(mediaId: number, enabled = true) {
	return useQuery({
		queryKey: ["progress", mediaId],
		queryFn: () => fetchProgress(mediaId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useSaveProgress() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: saveProgress,
		onSuccess: (progress) => {
			queryClient.setQueryData(["progress", progress.media_id], progress);
		},
	});
}

// Сброс позиции в начало (0) — это удаление серверной записи, иначе
// переоткрытие вернётся на старое место. Отсутствующую запись (404)
// считаем успехом: конечное состояние то же — прогресса нет.
async function deleteProgress(mediaId: number): Promise<void> {
	try {
		await apiFetch<unknown>(`/progress/${mediaId}`, { method: "DELETE" });
	} catch (error) {
		if (error instanceof ApiError && error.status === 404) {
			return;
		}
		throw error;
	}
}

export function useDeleteProgress() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: deleteProgress,
		onSuccess: (_data, mediaId) => {
			queryClient.setQueryData(["progress", mediaId], null);
		},
	});
}

// Незавершённый просмотр: явный флаг снят, до 90% длительности, но что-то
// уже отсмотрено или известна длительность.
function isUnfinished(entry: ProgressEntry): boolean {
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

async function fetchContinueWatching(
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
			isUnfinished(entry),
	);
}

export function useContinueWatching(kind: MediaKind) {
	return useQuery({
		queryKey: ["progress", "continue", kind],
		queryFn: () => fetchContinueWatching(kind),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

// Последний недослушанный трек для seeded-мини-плеера: свежих записей
// может быть несколько, а завершённая (дослушанная до конца) — самой
// новой, поэтому берём страницу и выбираем первую незавершённую.
// Сид фоновый и необязательный: без сессии в сеть не ходим, иначе
// apiFetch дёрнул бы refresh ради трека, который некому слушать.
// Ключ зеркалит sessionQueryKey из api/session (не экспортируется).
// Ошибки гасятся — плеер без сида просто стартует пустым.
export async function fetchLatestUnfinishedAudio(): Promise<Media | null> {
	const session = queryClient.getQueryData<AuthUser | null>(["session"]);
	if (session === null || session === undefined) {
		return null;
	}
	try {
		const params = new URLSearchParams({
			type: "audio",
			limit: String(CONTINUE_LIMIT),
			offset: "0",
		});
		const body = await apiFetch<unknown>(`/progress?${params.toString()}`);
		const parsed = progressListSchema.parse(body);
		for (const entry of parsed.items) {
			if (
				entry.media !== null &&
				entry.media !== undefined &&
				entry.media.type === "audio" &&
				isUnfinished(entry)
			) {
				return entry.media;
			}
		}
		return null;
	} catch (error) {
		// 401 после неудачного refresh — разлогинен, молча без сида.
		if (error instanceof ApiError && error.status === 401) {
			return null;
		}
		console.warn("Failed to fetch latest unfinished audio", error);
		return null;
	}
}

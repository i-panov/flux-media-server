import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { type Media, mediaSchema } from "../core/media";
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

async function fetchContinueWatching(): Promise<ContinueEntry[]> {
	const params = new URLSearchParams({
		limit: String(CONTINUE_LIMIT),
		offset: "0",
	});
	const body = await apiFetch<unknown>(`/progress?${params.toString()}`);
	const parsed = progressListSchema.parse(body);
	// Записи без медиа (удалённое или ещё не подгруженное) показывать нечем,
	// а прогресс по аудио сюда попадает из мобильного клиента: на странице
	// видео он открылся бы в плеере без картинки.
	return parsed.items.filter(
		(entry): entry is ContinueEntry =>
			entry.media !== null &&
			entry.media !== undefined &&
			entry.media.type === "video" &&
			isUnfinished(entry),
	);
}

export function useContinueWatching() {
	return useQuery({
		queryKey: ["progress", "continue"],
		queryFn: fetchContinueWatching,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

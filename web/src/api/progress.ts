import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { Media, MediaKind } from "../core/media";
import { queryClient } from "../queryClient";
import type { AuthUser } from "./auth";
import {
	ApiError,
	deleteProgress,
	fetchContinueWatching,
	fetchLatestUnfinishedAudio as fetchLatestUnfinishedAudioFromApi,
	fetchProgress,
	saveProgress,
} from "./client";

// Совместимый реэкспорт типа: схемы и fetch-функции живут в @flux/shared.
export type { ContinueEntry } from "./client";

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
			void queryClient.invalidateQueries({
				queryKey: ["progress", "continue"],
			});
		},
	});
}

export function useDeleteProgress() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: deleteProgress,
		onSuccess: (_data, mediaId) => {
			queryClient.setQueryData(["progress", mediaId], null);
			void queryClient.invalidateQueries({
				queryKey: ["progress", "continue"],
			});
		},
	});
}

export function useContinueWatching(kind: MediaKind) {
	return useQuery({
		queryKey: ["progress", "continue", kind],
		queryFn: () => fetchContinueWatching(kind),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

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
		return await fetchLatestUnfinishedAudioFromApi();
	} catch (error) {
		// 401 после неудачного refresh — разлогинен, молча без сида.
		if (error instanceof ApiError && error.status === 401) {
			return null;
		}
		console.warn("Failed to fetch latest unfinished audio", error);
		return null;
	}
}

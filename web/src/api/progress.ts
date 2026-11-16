import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import type { MediaKind } from "../core/media";
import {
	deleteProgress,
	fetchContinueWatching,
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

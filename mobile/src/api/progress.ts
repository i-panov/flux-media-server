import {
	type ContinueEntry,
	fetchContinueWatching,
	type MediaKind,
} from "@flux/shared";
import {
	type QueryClient,
	queryOptions,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { useCallback } from "react";

// Ряды «Продолжить» на главных: сервер уже отфильтровал завершённые
// записи и вложил медиа, поэтому клиенту остаётся только кэш.
export function continueWatchingQueryKey(kind: MediaKind) {
	return ["progress", "continue", kind] as const;
}

function continueWatchingQueryOptions(kind: MediaKind) {
	return queryOptions({
		queryKey: continueWatchingQueryKey(kind),
		queryFn: (): Promise<ContinueEntry[]> => fetchContinueWatching(kind),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useContinueWatching(kind: MediaKind) {
	return useQuery(continueWatchingQueryOptions(kind));
}

// Плеер сохраняет позицию напрямую через shared API, поэтому после
// успешного PUT/DELETE ряд должен сам перечитать серверный порядок.
export function invalidateContinueWatching(
	queryClient: QueryClient,
	kind: MediaKind,
): void {
	void queryClient.invalidateQueries({
		queryKey: continueWatchingQueryKey(kind),
	});
}

// Хук для плееров: сам достаёт QueryClient из провайдера, чтобы прогресс-
// модули не тянули его в каждый вызов.
export function useInvalidateContinueWatching(kind: MediaKind): () => void {
	const queryClient = useQueryClient();
	return useCallback(
		() => invalidateContinueWatching(queryClient, kind),
		[queryClient, kind],
	);
}

import {
	ApiError,
	addToCollection,
	type Collection,
	fetchCollectionItems,
	fetchCollectionStats,
	fetchCollections,
	type Media,
} from "@flux/shared";
import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";

export const collectionsQueryKey = ["collections"] as const;

function collectionsQueryOptions() {
	return queryOptions({
		queryKey: collectionsQueryKey,
		queryFn: () => fetchCollections(),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

// Один и тот же список делят экшены добавления и ряды на главных; фильтр
// по типу живёт в select, поэтому query-ключ остаётся общим с библиотекой.
function typedCollectionsQueryOptions(type: "video" | "audio") {
	return queryOptions({
		...collectionsQueryOptions(),
		select: (collections: Collection[]) =>
			collections.filter((collection) => collection.type === type),
	});
}

export function useCollections() {
	return useQuery(collectionsQueryOptions());
}

export function useVideoCollections() {
	return useQuery(typedCollectionsQueryOptions("video"));
}

export function useAudioCollections() {
	return useQuery(typedCollectionsQueryOptions("audio"));
}

export function collectionItemsQueryKey(collectionId: number) {
	return ["collections", collectionId, "items"] as const;
}

export function collectionStatsQueryKey(collectionId: number) {
	return ["collections", collectionId, "stats"] as const;
}

export function useCollectionItems(collectionId: number, enabled = true) {
	return useQuery({
		queryKey: collectionItemsQueryKey(collectionId),
		queryFn: (): Promise<Media[]> => fetchCollectionItems(collectionId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useCollectionStats(collectionId: number, enabled = true) {
	return useQuery({
		queryKey: collectionStatsQueryKey(collectionId),
		queryFn: () => fetchCollectionStats(collectionId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

// 409 — видео уже в этой коллекции. Это не сетевая ошибка: показываем
// пользователю понятное сообщение, а не общий текст сбоя.
export function isAlreadyInCollection(error: unknown): boolean {
	return error instanceof ApiError && error.status === 409;
}

export function useAddVideoToCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			collectionId,
			mediaId,
		}: {
			collectionId: number;
			mediaId: number;
		}) => addToCollection(collectionId, mediaId),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: collectionsQueryKey });
		},
	});
}

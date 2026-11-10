import {
	ApiError,
	addToCollection,
	type Collection,
	fetchCollections,
} from "@flux/shared";
import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";

export const collectionsQueryKey = ["collections"] as const;

// Экран деталей видео работает только с видеоколлекциями; фильтр живёт
// в select, чтобы query-ключ оставался общим с будущими экранами библиотеки.
function videoCollectionsQueryOptions() {
	return queryOptions({
		queryKey: collectionsQueryKey,
		queryFn: () => fetchCollections(),
		select: (collections: Collection[]) =>
			collections.filter((collection) => collection.type === "video"),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useVideoCollections() {
	return useQuery(videoCollectionsQueryOptions());
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

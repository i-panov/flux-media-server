import { fetchFavoriteMedia, toggleFavorite } from "@flux/shared";
import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";

// Избранное видео тянется целиком: сервер отдаёт только список записей,
// а экран деталей/local state должны знать, лежит ли текущее видео в нём.
// Ключ совпадает с web — инвалидация после toggle обновляет оба клиента
// в рамках одного приложения (mobile).
export const videoFavoritesQueryKey = ["favorites", "video", "all"] as const;

// Чистая функция для select и тестов: id избранных медиа.
export function favoriteIds(items: readonly { id: number }[]): Set<number> {
	return new Set(items.map((item) => item.id));
}

function videoFavoritesQueryOptions() {
	return queryOptions({
		queryKey: videoFavoritesQueryKey,
		queryFn: () => fetchFavoriteMedia("video"),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useFavoriteVideoIds() {
	return useQuery({
		...videoFavoritesQueryOptions(),
		select: favoriteIds,
	});
}

export function useToggleVideoFavorite() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			mediaId,
			favorite,
		}: {
			mediaId: number;
			favorite: boolean;
		}) => toggleFavorite(mediaId, favorite),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["favorites", "video"] });
		},
	});
}

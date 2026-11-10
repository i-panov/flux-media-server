import {
	fetchFavoriteMedia,
	type MediaType,
	toggleFavorite,
} from "@flux/shared";
import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";

// Избранное медиа тянется целиком: сервер отдаёт только список записей,
// а экраны/мини-плеер должны знать, лежит ли текущее медиа в нём.
// Ключ совпадает с web — инвалидация после toggle обновляет оба клиента
// в рамках одного приложения (mobile).
export type FavoriteMediaType = Extract<MediaType, "video" | "audio">;

export function favoritesQueryKey(type: FavoriteMediaType) {
	return ["favorites", type, "all"] as const;
}

export const videoFavoritesQueryKey = favoritesQueryKey("video");
export const audioFavoritesQueryKey = favoritesQueryKey("audio");

// Чистая функция для select и тестов: id избранных медиа.
export function favoriteIds(items: readonly { id: number }[]): Set<number> {
	return new Set(items.map((item) => item.id));
}

function favoritesQueryOptions(type: FavoriteMediaType) {
	return queryOptions({
		queryKey: favoritesQueryKey(type),
		queryFn: () => fetchFavoriteMedia(type),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useFavoriteMediaIds(type: FavoriteMediaType) {
	return useQuery({
		...favoritesQueryOptions(type),
		select: favoriteIds,
	});
}

export function useToggleMediaFavorite(type: FavoriteMediaType) {
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
			void queryClient.invalidateQueries({ queryKey: ["favorites", type] });
		},
	});
}

export function useFavoriteVideoIds() {
	return useFavoriteMediaIds("video");
}

export function useToggleVideoFavorite() {
	return useToggleMediaFavorite("video");
}

export function useFavoriteAudioIds() {
	return useFavoriteMediaIds("audio");
}

export function useToggleAudioFavorite() {
	return useToggleMediaFavorite("audio");
}

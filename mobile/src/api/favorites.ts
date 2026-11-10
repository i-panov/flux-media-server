import {
	fetchFavoriteArtistIds,
	fetchFavoriteMedia,
	type Media,
	type MediaType,
	toggleArtistFavorite,
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

export interface ToggleMediaFavoriteInput {
	mediaId: number;
	/** Текущее состояние: true означает «уже в избранном». */
	favorite: boolean;
	/** Добавляемая запись для оптимистичного ряда; у удаления не нужна. */
	media?: Media;
}

// Оптимистичное состояние списка избранного: удаление фильтрует запись,
// добавление ставит её первой для мгновенной видимости. Сервер отдаёт
// избранное по id ASC, поэтому после инвалидации порядок может отличаться.
// Без media добавить нечего, поэтому список не меняем — ждём инвалидации.
export function nextFavoriteMedia(
	items: readonly Media[],
	{ mediaId, favorite, media }: ToggleMediaFavoriteInput,
): Media[] {
	const without = items.filter((item) => item.id !== mediaId);
	if (favorite) {
		return without;
	}
	return media === undefined ? [...items] : [media, ...without];
}

function favoritesQueryOptions(type: FavoriteMediaType) {
	return queryOptions({
		queryKey: favoritesQueryKey(type),
		queryFn: () => fetchFavoriteMedia(type),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useFavoriteMedia(type: FavoriteMediaType): Media[] {
	return useQuery(favoritesQueryOptions(type)).data ?? [];
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
		mutationFn: ({ mediaId, favorite }: ToggleMediaFavoriteInput) =>
			toggleFavorite(mediaId, favorite),
		onMutate: async (input) => {
			const queryKey = favoritesQueryKey(type);
			await queryClient.cancelQueries({ queryKey });
			const previous = queryClient.getQueryData<Media[]>(queryKey);
			if (previous !== undefined) {
				queryClient.setQueryData<Media[]>(
					queryKey,
					nextFavoriteMedia(previous, input),
				);
			}
			return { previous };
		},
		onError: (_error, _input, context) => {
			if (context?.previous !== undefined) {
				queryClient.setQueryData(favoritesQueryKey(type), context.previous);
			}
		},
		onSettled: () => {
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

// Избранные артисты: ключ отдельный от медиа (id приходят из тех же
// /favorites, но набор другой), поэтому инвалидация не трогает треки.
export const artistFavoritesQueryKey = ["favorites", "artists", "all"] as const;

// Оптимистичное состояние сердечка артиста: добавление/удаление id сразу,
// откат — из снимка предыдущего Set в onError.
export function nextFavoriteArtistIds(
	ids: ReadonlySet<number>,
	artistId: number,
	favorite: boolean,
): Set<number> {
	const next = new Set(ids);
	if (favorite) {
		next.delete(artistId);
	} else {
		next.add(artistId);
	}
	return next;
}

export function useFavoriteArtistIds() {
	return useQuery({
		queryKey: artistFavoritesQueryKey,
		queryFn: () => fetchFavoriteArtistIds(),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useToggleArtistFavorite() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			artistId,
			favorite,
		}: {
			artistId: number;
			favorite: boolean;
		}) => toggleArtistFavorite(artistId, favorite),
		onMutate: async ({ artistId, favorite }) => {
			await queryClient.cancelQueries({ queryKey: artistFavoritesQueryKey });
			const previous = queryClient.getQueryData<Set<number>>(
				artistFavoritesQueryKey,
			);
			if (previous !== undefined) {
				queryClient.setQueryData<Set<number>>(
					artistFavoritesQueryKey,
					nextFavoriteArtistIds(previous, artistId, favorite),
				);
			}
			return { previous };
		},
		onError: (_error, _input, context) => {
			if (context?.previous !== undefined) {
				queryClient.setQueryData(artistFavoritesQueryKey, context.previous);
			}
		},
		onSettled: () => {
			void queryClient.invalidateQueries({
				queryKey: ["favorites", "artists"],
			});
		},
	});
}

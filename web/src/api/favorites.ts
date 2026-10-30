import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { z } from "zod";
import { type Media, type MediaType, mediaSchema } from "../core/media";
import { ApiError, apiFetch } from "./client";

const favoriteSchema = z.object({
	id: z.number(),
	user_id: z.number(),
	media_id: z.number().nullish(),
	artist_id: z.number().nullish(),
	media: mediaSchema.nullish(),
	created_at: z.string(),
});

const favoritesListSchema = z.object({
	items: z.array(favoriteSchema),
	total: z.number(),
	limit: z.number(),
	offset: z.number(),
});

// Верхняя граница API — 200. Тянем все страницы один раз: секция
// «Избранное» показывает медиа, а сердечки получают тот же набор через
// select — без второго запроса за теми же данными.
const FAVORITES_LIMIT = 200;

function favoritesAllQueryOptions(type: MediaType) {
	return queryOptions({
		queryKey: ["favorites", type, "all"],
		queryFn: async () => {
			const media: Media[] = [];
			let offset = 0;
			let total = 0;
			do {
				const body = await apiFetch<unknown>(
					`/favorites?type=${type}&limit=${FAVORITES_LIMIT}&offset=${offset}`,
				);
				const page = favoritesListSchema.parse(body);
				total = page.total;
				for (const entry of page.items) {
					if (entry.media !== null && entry.media !== undefined) {
						media.push(entry.media);
					}
				}
				const fetched = page.items.length;
				if (fetched === 0) {
					break;
				}
				offset += fetched;
			} while (offset < total);
			return media;
		},
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useFavoriteMedia(type: MediaType): Media[] {
	return useQuery(favoritesAllQueryOptions(type)).data ?? [];
}

export function useFavoriteIds(type: MediaType) {
	return useQuery({
		...favoritesAllQueryOptions(type),
		select: (media: Media[]) => new Set(media.map((item) => item.id)),
	});
}

export function useToggleFavorite(type: MediaType) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async ({
			mediaId,
			favorite,
		}: {
			mediaId: number;
			favorite: boolean;
		}) => {
			try {
				await apiFetch<unknown>(`/media/${mediaId}/favorite`, {
					method: favorite ? "DELETE" : "POST",
				});
			} catch (error) {
				// 409 на POST — уже в избранном, 404 на DELETE — уже
				// удалено в другой вкладке. Оба случая лечим инвалидацией.
				const stale =
					(!favorite && error instanceof ApiError && error.status === 409) ||
					(favorite && error instanceof ApiError && error.status === 404);
				if (stale) {
					return;
				}
				throw error;
			}
		},
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["favorites", type] });
		},
	});
}

const artistFavoritesKey = ["favorites", "artists", "all"] as const;

// Избранные артисты живут отдельно от медиа: в GET /favorites без фильтра
// по типу их строки (media_id NULL, artist_id задан) приходят вместе
// с медиа-избранным — забираем только id артистов.
function artistFavoritesQueryOptions() {
	return queryOptions({
		queryKey: artistFavoritesKey,
		queryFn: async () => {
			const ids = new Set<number>();
			let offset = 0;
			let total = 0;
			do {
				const body = await apiFetch<unknown>(
					`/favorites?limit=${FAVORITES_LIMIT}&offset=${offset}`,
				);
				const page = favoritesListSchema.parse(body);
				total = page.total;
				for (const entry of page.items) {
					if (entry.artist_id !== null && entry.artist_id !== undefined) {
						ids.add(entry.artist_id);
					}
				}
				const fetched = page.items.length;
				if (fetched === 0) {
					break;
				}
				offset += fetched;
			} while (offset < total);
			return ids;
		},
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useFavoriteArtistIds() {
	return useQuery(artistFavoritesQueryOptions());
}

export function useToggleArtistFavorite() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async ({
			artistId,
			favorite,
		}: {
			artistId: number;
			favorite: boolean;
		}) => {
			try {
				if (favorite) {
					await apiFetch<unknown>(`/favorites/artist?artist_id=${artistId}`, {
						method: "DELETE",
					});
				} else {
					await apiFetch<unknown>("/favorites/artist", {
						method: "POST",
						body: JSON.stringify({ artist_id: artistId }),
					});
				}
			} catch (error) {
				// 409 на POST — уже в избранном, 404 на DELETE — уже
				// удалено в другой вкладке. Оба случая лечим инвалидацией.
				const stale =
					(!favorite && error instanceof ApiError && error.status === 409) ||
					(favorite && error instanceof ApiError && error.status === 404);
				if (stale) {
					return;
				}
				throw error;
			}
		},
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: artistFavoritesKey });
		},
	});
}

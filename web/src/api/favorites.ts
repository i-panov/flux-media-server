import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import type { Media, MediaType } from "../core/media";
import {
	fetchFavoriteArtistIds,
	fetchFavoriteMedia,
	toggleArtistFavorite,
	toggleFavorite,
} from "./client";

function favoritesAllQueryOptions(type: MediaType) {
	return queryOptions({
		queryKey: ["favorites", type, "all"],
		queryFn: () => fetchFavoriteMedia(type),
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

const artistFavoritesKey = ["favorites", "artists", "all"] as const;

function artistFavoritesQueryOptions() {
	return queryOptions({
		queryKey: artistFavoritesKey,
		queryFn: () => fetchFavoriteArtistIds(),
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
		mutationFn: ({
			artistId,
			favorite,
		}: {
			artistId: number;
			favorite: boolean;
		}) => toggleArtistFavorite(artistId, favorite),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: artistFavoritesKey });
		},
	});
}

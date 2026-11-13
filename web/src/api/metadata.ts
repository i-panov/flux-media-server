import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export { updateMetadata };
import { z } from "zod";
import {
	type MetadataInput,
	updateMetadata,
} from "@flux/shared";
import { apiFetch } from "./client";

export function useUpdateMetadata(mediaId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: MetadataInput) => updateMetadata(mediaId, input),
		onSuccess: (media) => {
			// Детальная страница и все списки: название/обложка/теги
			// могли поменяться у любого элемента.
			queryClient.setQueryData(["media", media.id], media);
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

export interface ArtistEntry {
	id: number;
	name: string;
	has_cover: boolean;
	updated_at: string;
}

const artistEntrySchema = z.object({
	id: z.number(),
	name: z.string(),
	has_cover: z.boolean().default(false),
	updated_at: z.string().default(""),
});

export function useMediaArtists() {
	return useQuery({
		queryKey: ["artists"],
		queryFn: async (): Promise<ArtistEntry[]> => {
			const body = await apiFetch<unknown>("/artists");
			const parsed = (body as { items?: unknown }).items ?? body;
			const entries = z
				.array(artistEntrySchema)
				.parse(parsed)
				.map((artist) => ({
					id: artist.id,
					name: artist.name,
					has_cover: artist.has_cover,
					updated_at: artist.updated_at,
				}));
			const seen = new Set<string>();
			return entries
				.filter((artist) => {
					if (seen.has(artist.name)) {
						return false;
					}
					seen.add(artist.name);
					return true;
				})
				.sort((a, b) => a.name.localeCompare(b.name));
		},
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useArtist(artistId: number) {
	const artists = useMediaArtists();
	const artist = (artists.data ?? []).find((item) => item.id === artistId);
	return {
		artist,
		isPending: artists.isPending,
		isError: artists.isError,
		refetch: artists.refetch,
	};
}

export async function renameArtist(id: number, name: string) {
	const body = await apiFetch<unknown>(`/artists/${id}`, {
		method: "PUT",
		body: JSON.stringify({ name }),
	});
	return artistEntrySchema.parse(body);
}

export function useRenameArtist() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, name }: { id: number; name: string }) =>
			renameArtist(id, name),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["artists"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { type Media, mediaSchema } from "../core/media";
import { apiFetch } from "./client";

export interface MetadataInput {
	title: string;
	artists: string[];
	album?: string;
	genre?: string;
	year?: number;
	description?: string;
	sourceUrl?: string;
}

// Бэкенд различает «не передано» и «пусто» указателями: пустые строки
// не шлём, чтобы не затирать (очистка — только у source_url, как во
// Flutter: пустое при непустом исходном считается осознанной очисткой).
export async function updateMetadata(
	mediaId: number,
	input: MetadataInput,
): Promise<Media> {
	const body: Record<string, unknown> = {
		title: input.title,
		artists: input.artists,
	};
	if (input.album !== undefined && input.album !== "") {
		body.album = input.album;
	}
	if (input.genre !== undefined && input.genre !== "") {
		body.genre = input.genre;
	}
	if (input.year !== undefined) {
		body.year = input.year;
	}
	if (input.description !== undefined && input.description !== "") {
		body.description = input.description;
	}
	if (input.sourceUrl !== undefined) {
		body.source_url = input.sourceUrl;
	}
	const response = await apiFetch<unknown>(`/metadata/${mediaId}`, {
		method: "PUT",
		body: JSON.stringify(body),
	});
	return mediaSchema.parse(response);
}

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
}

const artistEntrySchema = z.object({
	id: z.number(),
	name: z.string(),
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
				.map((artist) => ({ id: artist.id, name: artist.name }));
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

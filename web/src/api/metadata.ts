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

export function useMediaArtists() {
	return useQuery({
		queryKey: ["artists"],
		queryFn: async (): Promise<string[]> => {
			const body = await apiFetch<unknown>("/artists");
			const parsed = (body as { items?: unknown }).items ?? body;
			const names = z
				.array(z.object({ name: z.string() }))
				.parse(parsed)
				.map((artist) => artist.name);
			return [...new Set(names)].sort((a, b) => a.localeCompare(b));
		},
		retry: false,
		refetchOnWindowFocus: false,
	});
}

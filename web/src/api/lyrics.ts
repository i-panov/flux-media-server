import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { ApiError, apiFetch } from "./client";

const lyricsSchema = z.object({
	id: z.number(),
	media_id: z.number(),
	lyrics_text: z.string(),
	translation: z.string(),
	sync_data: z.string(),
	source: z.string(),
	created_at: z.string(),
	updated_at: z.string(),
});

export type Lyrics = z.infer<typeof lyricsSchema>;

async function fetchLyrics(mediaId: number): Promise<Lyrics | null> {
	try {
		const body = await apiFetch<unknown>(`/media/${mediaId}/lyrics`);
		return lyricsSchema.parse(body);
	} catch (error) {
		if (error instanceof ApiError && error.status === 404) {
			return null;
		}
		throw error;
	}
}

export function useLyrics(mediaId: number, enabled = true) {
	return useQuery({
		queryKey: ["lyrics", mediaId],
		queryFn: () => fetchLyrics(mediaId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useSaveLyrics(mediaId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			lyricsText: string;
			translation: string;
			syncData?: string;
			source?: string;
		}) =>
			apiFetch<unknown>(`/media/${mediaId}/lyrics`, {
				method: "PUT",
				body: JSON.stringify({
					lyrics_text: input.lyricsText,
					translation: input.translation,
					sync_data: input.syncData ?? "",
					source: input.source ?? "user",
					// Редактор отправляет полное состояние: пустое поле — это
					// очистка, а не «поле не передано».
					clear: true,
				}),
			}),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["lyrics", mediaId] });
		},
	});
}

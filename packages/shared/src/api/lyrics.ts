import { z } from "zod";
import { ApiError, apiFetch } from "./client";

export const lyricsSchema = z.object({
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

export async function fetchLyrics(mediaId: number): Promise<Lyrics | null> {
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

export interface SaveLyricsInput {
	lyricsText: string;
	translation: string;
	syncData?: string;
	source?: string;
}

export async function saveLyrics(
	mediaId: number,
	input: SaveLyricsInput,
): Promise<void> {
	await apiFetch<unknown>(`/media/${mediaId}/lyrics`, {
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
	});
}

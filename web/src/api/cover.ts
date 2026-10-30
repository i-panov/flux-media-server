import { useMutation, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { apiFetch } from "./client";

// Сервер принимает JPEG/PNG/WebP до 10 МБ и отвечает только cover_url.
const coverResponseSchema = z.object({
	cover_url: z.string(),
});

export async function uploadCover(
	mediaId: number,
	file: File,
	signal?: AbortSignal,
): Promise<string> {
	const form = new FormData();
	form.set("cover", file, file.name);
	const body = await apiFetch<unknown>(`/media/${mediaId}/cover`, {
		method: "PUT",
		body: form,
		signal,
	});
	return coverResponseSchema.parse(body).cover_url;
}

export function useUploadCover(mediaId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (file: File) => uploadCover(mediaId, file),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

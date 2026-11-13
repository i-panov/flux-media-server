import { parseCoverResponse } from "@flux/shared";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { apiFetch } from "./client";

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
	return parseCoverResponse(body);
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

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { ApiError, apiFetch } from "./client";

const progressSchema = z.object({
	id: z.number(),
	user_id: z.number(),
	media_id: z.number(),
	position: z.number(),
	duration: z.number(),
	completed: z.boolean(),
	updated_at: z.string(),
});

export type Progress = z.infer<typeof progressSchema>;

async function fetchProgress(mediaId: number): Promise<Progress | null> {
	try {
		const body = await apiFetch<unknown>(`/progress/${mediaId}`);
		return progressSchema.parse(body);
	} catch (error) {
		if (error instanceof ApiError && error.status === 404) {
			return null;
		}
		throw error;
	}
}

async function saveProgress({
	mediaId,
	position,
	duration,
	completed,
}: {
	mediaId: number;
	position: number;
	duration: number;
	completed: boolean;
}): Promise<Progress> {
	const body = await apiFetch<unknown>(`/progress/${mediaId}`, {
		method: "PUT",
		body: JSON.stringify({ position, duration, completed }),
	});
	return progressSchema.parse(body);
}

export function useProgress(mediaId: number, enabled = true) {
	return useQuery({
		queryKey: ["progress", mediaId],
		queryFn: () => fetchProgress(mediaId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useSaveProgress() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: saveProgress,
		onSuccess: (progress) => {
			queryClient.setQueryData(["progress", progress.media_id], progress);
		},
	});
}

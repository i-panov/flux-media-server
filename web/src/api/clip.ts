import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiFetch } from "./client";

export interface ClipTask {
	id: number;
	source_media_id: number;
	start_seconds: number;
	end_seconds: number;
	title: string;
	status: "queued" | "processing" | "done" | "error";
	progress: number;
	error?: string;
	output_media_id?: number;
}

export function useCreateClip() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			mediaID: number;
			start: number;
			end: number;
			title?: string;
		}) =>
			apiFetch<ClipTask>(`/media/${input.mediaID}/clip`, {
				method: "POST",
				body: JSON.stringify({
					start: input.start,
					end: input.end,
					title: input.title,
				}),
			}),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["clips"] });
		},
	});
}

export function useClip(id: number | null) {
	return useQuery({
		queryKey: ["clips", id],
		queryFn: () => apiFetch<ClipTask>(`/clips/${id}`),
		enabled: id !== null && id > 0,
		refetchInterval: (query) =>
			query.state.data?.status === "queued" ||
			query.state.data?.status === "processing"
				? 2000
				: false,
	});
}

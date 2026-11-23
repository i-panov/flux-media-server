import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

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
	const queryClient = useQueryClient();
	return useQuery({
		queryKey: ["clips", id],
		queryFn: async () => {
			const task = await apiFetch<ClipTask>(`/clips/${id}`);
			if (task.status === "done") {
				void queryClient.invalidateQueries({ queryKey: ["media"] });
			}
			return task;
		},
		enabled: id !== null && id > 0,
		refetchInterval: (query) => {
			const status = query.state.data?.status;
			return status === "queued" || status === "processing" ? 2000 : false;
		},
	});
}

export function useCancelClip() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<void>(`/clips/${id}`, { method: "DELETE" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["clips"] });
		},
	});
}

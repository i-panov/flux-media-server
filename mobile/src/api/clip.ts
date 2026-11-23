import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";

const clipTaskSchema = z.object({
	id: z.number(),
	source_media_id: z.number(),
	start_seconds: z.number(),
	end_seconds: z.number(),
	title: z.string(),
	status: z.enum(["queued", "processing", "done", "error"]),
	progress: z.number(),
	error: z.string().optional(),
	output_media_id: z.number().optional(),
});

export type ClipTask = z.infer<typeof clipTaskSchema>;

export function useCreateClip() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async (input: {
			mediaID: number;
			start: number;
			end: number;
			title?: string;
		}) => {
			const body = await apiFetch<unknown>(`/media/${input.mediaID}/clip`, {
				method: "POST",
				body: JSON.stringify({
					start: input.start,
					end: input.end,
					title: input.title,
				}),
			});
			return clipTaskSchema.parse(body);
		},
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
			const task = clipTaskSchema.parse(
				await apiFetch<unknown>(`/clips/${id}`),
			);
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

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { apiFetch } from "./client";

const transcodeItemSchema = z.object({
	id: z.number(),
	status: z.string(),
	progress: z.number(),
	speed: z.number(),
	eta_seconds: z.number(),
	error: z.string().nullish(),
	filename: z.string(),
	media_id: z.number(),
});

export type TranscodeItem = z.infer<typeof transcodeItemSchema>;

const transcodesSchema = z.array(transcodeItemSchema);

const transcodeStatusSchema = z.object({
	id: z.number(),
	status: z.string(),
	error: z.string().nullish(),
	media: z.unknown().nullish(),
	progress: z.number().nullish(),
	speed: z.number().nullish(),
	eta_seconds: z.number().nullish(),
});

export type TranscodeStatus = z.infer<typeof transcodeStatusSchema>;

export async function listTranscodes(
	signal?: AbortSignal,
): Promise<TranscodeItem[]> {
	const body = await apiFetch<unknown>("/admin/transcodes", { signal });
	return transcodesSchema.parse(body);
}

export async function getTranscodeStatus(id: number): Promise<TranscodeStatus> {
	const body = await apiFetch<unknown>(`/media/transcodes/${id}`);
	return transcodeStatusSchema.parse(body);
}

export async function cancelTranscode(id: number): Promise<void> {
	await apiFetch<unknown>(`/media/transcodes/${id}`, { method: "DELETE" });
}

export function useTranscodesQuery(options?: { enabled?: boolean }) {
	return useQuery({
		queryKey: ["admin", "transcodes"],
		queryFn: ({ signal }) => listTranscodes(signal),
		retry: false,
		refetchOnWindowFocus: false,
		refetchInterval: 2000,
		enabled: options?.enabled ?? true,
	});
}

export function useCancelTranscode() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => cancelTranscode(id),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "transcodes"] });
		},
	});
}

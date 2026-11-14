import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { apiFetch } from "./client";

const jobSchema = z.object({
	id: z.string(),
	status: z.enum([
		"queued",
		"downloading",
		"importing",
		"processing",
		"done",
		"error",
		"cancelled",
	]),
	stage: z.string().optional(),
	progress: z.number().optional(),
	error: z.string().optional(),
	upload_job_id: z.number().optional(),
	media_id: z.number().optional(),
	title: z.string().optional(),
	filename: z.string().optional(),
});

export type MediaLoaderJob = z.infer<typeof jobSchema>;

interface MediaLoaderInput {
	url: string;
	audioOnly: boolean;
	format: string;
	quality: string;
}

async function startMediaLoader(
	input: MediaLoaderInput,
): Promise<MediaLoaderJob> {
	const body = await apiFetch<unknown>("/admin/downloads", {
		method: "POST",
		body: JSON.stringify({
			url: input.url,
			audio_only: input.audioOnly,
			format: input.format,
			quality: input.audioOnly ? "" : input.quality,
		}),
	});
	return jobSchema.parse(body);
}

async function fetchMediaLoaderJob(id: string): Promise<MediaLoaderJob> {
	return jobSchema.parse(await apiFetch<unknown>(`/admin/downloads/${id}`));
}

export async function cancelMediaLoaderJob(id: string): Promise<void> {
	await apiFetch<unknown>(`/admin/downloads/${id}`, { method: "DELETE" });
}

export function useMediaLoaderJob(id: string | null) {
	return useQuery({
		queryKey: ["media-loader", id],
		queryFn: () => fetchMediaLoaderJob(id ?? ""),
		enabled: id !== null,
		refetchInterval: (query) => {
			const status = query.state.data?.status;
			return status === undefined ||
				status === "queued" ||
				status === "downloading" ||
				status === "importing" ||
				status === "processing"
				? 2000
				: false;
		},
	});
}

export function useStartMediaLoader() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: startMediaLoader,
		onSuccess: (job) => {
			queryClient.setQueryData(["media-loader", job.id], job);
		},
	});
}

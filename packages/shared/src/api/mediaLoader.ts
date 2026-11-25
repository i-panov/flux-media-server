import { z } from "zod";
import { apiFetch } from "./client";

// Задания media-loader (link-download): общий контракт web и mobile.
export const mediaLoaderJobSchema = z.object({
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
export type MediaLoaderJob = z.infer<typeof mediaLoaderJobSchema>;

export interface MediaLoaderInput {
	url: string;
	audioOnly: boolean;
	format: string;
	quality: string;
}

const jobListSchema = z.array(mediaLoaderJobSchema);

const ACTIVE_STATUSES: ReadonlySet<MediaLoaderJob["status"]> = new Set([
	"queued",
	"downloading",
	"importing",
	"processing",
]);

export function isActiveMediaLoaderJob(job: MediaLoaderJob): boolean {
	return ACTIVE_STATUSES.has(job.status);
}

export async function startMediaLoader(
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
	return mediaLoaderJobSchema.parse(body);
}

export async function fetchMediaLoaderJobs(): Promise<MediaLoaderJob[]> {
	return jobListSchema.parse(await apiFetch<unknown>("/admin/downloads"));
}

export async function cancelMediaLoaderJob(id: string): Promise<void> {
	await apiFetch<unknown>(`/admin/downloads/${id}`, { method: "DELETE" });
}

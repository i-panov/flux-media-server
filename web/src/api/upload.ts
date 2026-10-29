import { z } from "zod";
import { mediaSchema } from "../core/media";
import { apiFetch } from "./client";

export type UploadType = "video" | "audio" | "image";

const enqueueSchema = z.object({
	job_id: z.number(),
	job_type: z.enum(["upload", "transcode"]).optional(),
});

const jobSchema = z.object({
	id: z.number(),
	status: z.string(),
	error: z.string().nullish(),
	// Похожий мем: приходит только со статусом duplicate.
	duplicate: z
		.object({
			id: z.number(),
			title: z.string(),
		})
		.nullish(),
	media: mediaSchema.nullish(),
	// Прогресс нормализации видео, 0–100.
	progress: z.number().nullish(),
	speed: z.number().nullish(),
	eta_seconds: z.number().nullish(),
});

export type UploadJob = z.infer<typeof jobSchema>;

export interface EnqueuedUpload {
	jobId: number;
	jobType: "upload" | "transcode";
}

export async function enqueueUpload(
	file: File,
	type: UploadType,
	force = false,
): Promise<EnqueuedUpload> {
	const form = new FormData();
	form.set("file", file);
	form.set("media_type", type);
	if (force) {
		form.set("force", "true");
	}
	const body = await apiFetch<unknown>("/media/upload", {
		method: "POST",
		body: form,
	});
	const parsed = enqueueSchema.parse(body);
	return {
		jobId: parsed.job_id,
		// Старые ответы без job_type: видео всегда идёт через транскод.
		jobType: parsed.job_type ?? (type === "video" ? "transcode" : "upload"),
	};
}

export async function fetchUploadJob(
	jobType: "upload" | "transcode",
	jobId: number,
): Promise<UploadJob> {
	const path =
		jobType === "transcode"
			? `/media/transcodes/${jobId}`
			: `/media/uploads/${jobId}`;
	const body = await apiFetch<unknown>(path);
	return jobSchema.parse(body);
}

export async function cancelUploadJob(
	jobType: "upload" | "transcode",
	jobId: number,
): Promise<void> {
	const path =
		jobType === "transcode"
			? `/media/transcodes/${jobId}`
			: `/media/uploads/${jobId}`;
	await apiFetch<unknown>(path, { method: "DELETE" });
}

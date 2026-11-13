import { z } from "zod";
import { mediaSchema } from "../core/media";

export type UploadType = "video" | "audio" | "image";
export type UploadJobKind = "upload" | "transcode";

export const MAX_UPLOAD_BYTES = 2 * 1024 * 1024 * 1024;
export const UPLOAD_POLL_INTERVAL_MS = 900;

export const enqueueSchema = z.object({
	job_id: z.number(),
	job_type: z.enum(["upload", "transcode"]).optional(),
});

export const uploadJobSchema = z.object({
	id: z.number(),
	status: z.string(),
	error: z.string().nullish(),
	duplicate: z
		.object({ id: z.number(), title: z.string() })
		.nullish(),
	media: mediaSchema.nullish(),
	progress: z.number().nullish(),
	speed: z.number().nullish(),
	eta_seconds: z.number().nullish(),
});

export type UploadJob = z.infer<typeof uploadJobSchema>;

export interface EnqueuedUpload {
	jobId: number;
	jobType: UploadJobKind;
}

export function parseEnqueueResponse(
	body: unknown,
	type: UploadType,
): EnqueuedUpload {
	const parsed = enqueueSchema.parse(body);
	return {
		jobId: parsed.job_id,
		jobType: parsed.job_type ?? (type === "video" ? "transcode" : "upload"),
	};
}

export function parseUploadJob(body: unknown): UploadJob {
	return uploadJobSchema.parse(body);
}

export function uploadJobPath(jobType: UploadJobKind, jobId: number): string {
	return jobType === "transcode"
		? `/media/transcodes/${jobId}`
		: `/media/uploads/${jobId}`;
}

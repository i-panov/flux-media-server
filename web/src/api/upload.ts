import {
	type EnqueuedUpload,
	parseEnqueueResponse,
	parseUploadJob,
	type UploadJob,
	type UploadType,
	uploadJobPath,
} from "@flux/shared";
import { apiFetch } from "./client";

export type { UploadType };

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
	return parseEnqueueResponse(body, type);
}

export async function fetchUploadJob(
	jobType: "upload" | "transcode",
	jobId: number,
): Promise<UploadJob> {
	const body = await apiFetch<unknown>(uploadJobPath(jobType, jobId));
	return parseUploadJob(body);
}

export async function cancelUploadJob(
	jobType: "upload" | "transcode",
	jobId: number,
): Promise<void> {
	await apiFetch<unknown>(uploadJobPath(jobType, jobId), {
		method: "DELETE",
	});
}

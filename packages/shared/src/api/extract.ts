import { z } from "zod";
import { type Media, mediaSchema } from "../core/media";
import { ApiError, apiFetch } from "./client";

// Извлечение аудиодорожки: схемы и запросы общие для web и mobile.
// Клиенты оставляют у себя только UX-политику и хуки.
export const extractJobStatusSchema = z.object({
	id: z.number(),
	status: z.string(),
	error: z.string().nullish(),
	media: mediaSchema.nullish(),
});
export type ExtractJobStatus = z.infer<typeof extractJobStatusSchema>;

const extractJobRefSchema = z.object({
	job_id: z.number().int().positive(),
});

export type ExtractStartResult =
	| { kind: "track"; track: Media; alreadyExtracted: true }
	| { kind: "job"; jobId: number; alreadyExtracted: false };

export async function fetchExtractedAudio(
	mediaId: number,
): Promise<Media | null> {
	try {
		const body = await apiFetch<unknown>(`/media/${mediaId}/extracted`);
		return mediaSchema.parse(body);
	} catch (error) {
		if (error instanceof ApiError && error.status === 404) {
			return null;
		}
		throw error;
	}
}

// POST отдаёт либо готовый трек (200), либо задание (202 {job_id}).
export async function startExtract(
	mediaId: number,
): Promise<ExtractStartResult> {
	const body = await apiFetch<unknown>(`/media/${mediaId}/extract`, {
		method: "POST",
	});
	if (typeof body === "object" && body !== null && "job_id" in body) {
		return {
			kind: "job",
			jobId: extractJobRefSchema.parse(body).job_id,
			alreadyExtracted: false,
		};
	}
	return {
		kind: "track",
		track: mediaSchema.parse(body),
		alreadyExtracted: true,
	};
}

export async function fetchExtractStatus(
	jobId: number,
	signal?: AbortSignal,
): Promise<ExtractJobStatus> {
	return extractJobStatusSchema.parse(
		await apiFetch<unknown>(`/media/extract/${jobId}`, { signal }),
	);
}

export async function cancelExtractJob(jobId: number): Promise<void> {
	await apiFetch<unknown>(`/media/extract/${jobId}`, { method: "DELETE" });
}

import { z } from "zod";
import { apiFetch } from "./client";

// Задача нарезки фрагмента: контракт общий для web и mobile.
export const clipTaskSchema = z.object({
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

export interface CreateClipInput {
	mediaID: number;
	start: number;
	end: number;
	title?: string;
}

export async function createClip(input: CreateClipInput): Promise<ClipTask> {
	const body = await apiFetch<unknown>(`/media/${input.mediaID}/clip`, {
		method: "POST",
		body: JSON.stringify({
			start: input.start,
			end: input.end,
			title: input.title,
		}),
	});
	return clipTaskSchema.parse(body);
}

export async function fetchClip(id: number): Promise<ClipTask> {
	return clipTaskSchema.parse(await apiFetch<unknown>(`/clips/${id}`));
}

export async function cancelClip(id: number): Promise<void> {
	await apiFetch<unknown>(`/clips/${id}`, { method: "DELETE" });
}

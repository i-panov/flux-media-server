import { z } from "zod";
import { mediaSchema } from "../core/media";
import { ApiError, apiFetch } from "./client";
import { collectionSchema } from "./collections";

export const trashSchema = z.object({
	collections: z.array(collectionSchema),
	media: z.array(mediaSchema),
});

export type TrashData = z.infer<typeof trashSchema>;

export function parseTrash(body: unknown): TrashData {
	return trashSchema.parse(body);
}

export async function fetchTrash(signal?: AbortSignal): Promise<TrashData> {
	return parseTrash(await apiFetch<unknown>("/trash", { signal }));
}

export function isTrashEmpty(data: TrashData): boolean {
	return data.collections.length + data.media.length === 0;
}

export function trashCount(data: TrashData): number {
	return data.collections.length + data.media.length;
}

export function isTrashMissing(error: unknown): boolean {
	return error instanceof ApiError && error.status === 404;
}

export type TrashErrorKey =
	| "trash.missingError"
	| "trash.conflictError"
	| "trash.forbiddenError"
	| "trash.actionError";

export function trashErrorKey(error: unknown): TrashErrorKey {
	if (!(error instanceof ApiError)) return "trash.actionError";
	switch (error.status) {
		case 404:
			return "trash.missingError";
		case 409:
			return "trash.conflictError";
		case 403:
			return "trash.forbiddenError";
		default:
			return "trash.actionError";
	}
}

export const trashActions = {
	restoreMedia: (id: number) =>
		apiFetch<unknown>(`/trash/media/${id}/restore`, { method: "POST" }),
	purgeMedia: (id: number) =>
		apiFetch<unknown>(`/trash/media/${id}`, { method: "DELETE" }),
	restoreCollection: (id: number) =>
		apiFetch<unknown>(`/trash/collections/${id}/restore`, { method: "POST" }),
	purgeCollection: (id: number) =>
		apiFetch<unknown>(`/trash/collections/${id}`, { method: "DELETE" }),
	emptyTrash: () => apiFetch<unknown>("/trash", { method: "DELETE" }),
} as const;

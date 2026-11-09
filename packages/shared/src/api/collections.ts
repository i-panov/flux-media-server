import { z } from "zod";
import { type Media, type MediaType, mediaSchema } from "../core/media";
import { apiFetch } from "./client";

export const collectionSchema = z.object({
	id: z.number(),
	user_id: z.number(),
	name: z.string(),
	type: z.string(),
	parent_id: z.number().nullish(),
	created_at: z.string(),
	updated_at: z.string(),
	deleted_at: z.unknown().optional(),
});

export type Collection = z.infer<typeof collectionSchema>;

const collectionsSchema = z.array(collectionSchema);

export const collectionStatsSchema = z.object({
	subcollections: z.number(),
	items: z.number(),
});

export type CollectionStats = z.infer<typeof collectionStatsSchema>;

// Частичный успех — норма для групповых операций: часть элементов могла
// уже лежать в целевой коллекции или отсутствовать в источнике.
// Go-бэкенд сериализует nil-слайсы как null (BulkItemsResult без omitempty):
// неиспользуемые массивы приходят именно null, а не отсутствуют.
export const bulkResultSchema = z.object({
	added: z.array(z.number()).nullish(),
	moved: z.array(z.number()).nullish(),
	removed: z.array(z.number()).nullish(),
	skipped: z.array(z.number()).nullish(),
});

export type BulkResult = z.infer<typeof bulkResultSchema>;

export async function fetchCollections(): Promise<Collection[]> {
	const body = await apiFetch<unknown>("/collections");
	return collectionsSchema.parse(body);
}

export async function fetchCollectionItems(
	collectionId: number,
): Promise<Media[]> {
	const body = await apiFetch<unknown>(`/collections/${collectionId}/items`);
	return z.array(mediaSchema).parse(body);
}

export async function fetchCollectionStats(
	collectionId: number,
): Promise<CollectionStats> {
	const body = await apiFetch<unknown>(`/collections/${collectionId}/stats`);
	return collectionStatsSchema.parse(body);
}

export function createCollection(
	name: string,
	type: MediaType,
): Promise<unknown> {
	return apiFetch<unknown>("/collections", {
		method: "POST",
		body: JSON.stringify({ name, type }),
	});
}

export function renameCollection(id: number, name: string): Promise<unknown> {
	return apiFetch<unknown>(`/collections/${id}`, {
		method: "PUT",
		body: JSON.stringify({ name }),
	});
}

export function deleteCollection(id: number): Promise<unknown> {
	return apiFetch<unknown>(`/collections/${id}`, { method: "DELETE" });
}

export function addToCollection(
	collectionId: number,
	mediaId: number,
): Promise<unknown> {
	return apiFetch<unknown>(`/collections/${collectionId}/items`, {
		method: "POST",
		body: JSON.stringify({ media_id: mediaId }),
	});
}

export async function bulkAddCollectionItems(
	collectionId: number,
	mediaIds: number[],
): Promise<BulkResult> {
	const body = await apiFetch<unknown>(
		`/collections/${collectionId}/items/bulk`,
		{
			method: "POST",
			body: JSON.stringify({ media_ids: mediaIds }),
		},
	);
	return bulkResultSchema.parse(body);
}

export function moveCollectionItem(
	sourceId: number,
	toCollectionId: number,
	mediaId: number,
): Promise<unknown> {
	return apiFetch<unknown>(`/collections/${sourceId}/items/move`, {
		method: "POST",
		body: JSON.stringify({
			media_id: mediaId,
			to_collection_id: toCollectionId,
		}),
	});
}

// Перенос коллекции под другого родителя (как во Flutter):
// parent_id шлём всегда — отсутствие ключа бэкенд читает как
// «не трогать», явный null переводит в корень.
export function moveCollection(
	id: number,
	parentId: number | null,
): Promise<unknown> {
	return apiFetch<unknown>(`/collections/${id}`, {
		method: "PUT",
		body: JSON.stringify({ parent_id: parentId }),
	});
}

export function removeFromCollection(
	collectionId: number,
	mediaId: number,
): Promise<unknown> {
	return apiFetch<unknown>(`/collections/${collectionId}/items/${mediaId}`, {
		method: "DELETE",
	});
}

export async function bulkRemoveCollectionItems(
	collectionId: number,
	mediaIds: number[],
): Promise<BulkResult> {
	const body = await apiFetch<unknown>(`/collections/${collectionId}/items`, {
		method: "DELETE",
		body: JSON.stringify({ media_ids: mediaIds }),
	});
	return bulkResultSchema.parse(body);
}

export interface BulkMoveCollectionItemsInput {
	mediaIds: number[];
	toCollectionId: number;
}

export async function bulkMoveCollectionItems(
	collectionId: number,
	{ mediaIds, toCollectionId }: BulkMoveCollectionItemsInput,
): Promise<BulkResult> {
	const body = await apiFetch<unknown>(
		`/collections/${collectionId}/items/move/bulk`,
		{
			method: "POST",
			body: JSON.stringify({
				media_ids: mediaIds,
				to_collection_id: toCollectionId,
			}),
		},
	);
	return bulkResultSchema.parse(body);
}

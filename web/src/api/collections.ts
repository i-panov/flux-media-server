import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { z } from "zod";
import { type MediaType, mediaSchema } from "../core/media";
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

function collectionsQueryOptions() {
	return queryOptions({
		queryKey: ["collections"],
		queryFn: async () => {
			const body = await apiFetch<unknown>("/collections");
			return collectionsSchema.parse(body);
		},
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useCollections() {
	return useQuery(collectionsQueryOptions());
}

export function useCollectionItems(collectionId: number, enabled = true) {
	return useQuery({
		queryKey: ["collections", collectionId, "items"],
		queryFn: async () => {
			const body = await apiFetch<unknown>(
				`/collections/${collectionId}/items`,
			);
			return z.array(mediaSchema).parse(body);
		},
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

const collectionStatsSchema = z.object({
	subcollections: z.number(),
	items: z.number(),
});

export function useCollectionStats(collectionId: number, enabled = true) {
	return useQuery({
		queryKey: ["collections", collectionId, "stats"],
		queryFn: async () => {
			const body = await apiFetch<unknown>(
				`/collections/${collectionId}/stats`,
			);
			return collectionStatsSchema.parse(body);
		},
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

const bulkResultSchema = z.object({
	added: z.array(z.number()).optional(),
	moved: z.array(z.number()).optional(),
	removed: z.array(z.number()).optional(),
	skipped: z.array(z.number()).optional(),
});

export function useBulkRemoveCollectionItems(collectionId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async (mediaIds: number[]) => {
			const body = await apiFetch<unknown>(
				`/collections/${collectionId}/items`,
				{
					method: "DELETE",
					body: JSON.stringify({ media_ids: mediaIds }),
				},
			);
			return bulkResultSchema.parse(body);
		},
		onSuccess: () => {
			void queryClient.invalidateQueries({
				queryKey: ["collections", collectionId, "items"],
			});
			void queryClient.invalidateQueries({
				queryKey: ["collections", collectionId, "stats"],
			});
		},
	});
}

export function useBulkMoveCollectionItems(collectionId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async ({
			mediaIds,
			toCollectionId,
		}: {
			mediaIds: number[];
			toCollectionId: number;
		}) => {
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
		},
		onSuccess: () => {
			void queryClient.invalidateQueries({
				queryKey: ["collections", collectionId, "items"],
			});
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
			void queryClient.invalidateQueries({
				queryKey: ["collections", collectionId, "stats"],
			});
		},
	});
}

export function useCreateCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ name, type }: { name: string; type: MediaType }) =>
			apiFetch<unknown>("/collections", {
				method: "POST",
				body: JSON.stringify({ name, type }),
			}),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
		},
	});
}

export function useRenameCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, name }: { id: number; name: string }) =>
			apiFetch<unknown>(`/collections/${id}`, {
				method: "PUT",
				body: JSON.stringify({ name }),
			}),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
		},
	});
}

export function useDeleteCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<unknown>(`/collections/${id}`, { method: "DELETE" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
		},
	});
}

export function useAddToCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			collectionId,
			mediaId,
		}: {
			collectionId: number;
			mediaId: number;
		}) =>
			apiFetch<unknown>(`/collections/${collectionId}/items`, {
				method: "POST",
				body: JSON.stringify({ media_id: mediaId }),
			}),
		onSuccess: (_data, variables) => {
			void queryClient.invalidateQueries({
				queryKey: ["collections", variables.collectionId, "items"],
			});
		},
	});
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

export function useMoveCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, parentId }: { id: number; parentId: number | null }) =>
			moveCollection(id, parentId),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
		},
	});
}

export function useMoveCollectionItem() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			sourceId,
			toCollectionId,
			mediaId,
		}: {
			sourceId: number;
			toCollectionId: number;
			mediaId: number;
		}) => moveCollectionItem(sourceId, toCollectionId, mediaId),
		onSuccess: (_data, variables) => {
			// Элемент уехал из исходной коллекции в целевую.
			void queryClient.invalidateQueries({
				queryKey: ["collections", variables.sourceId, "items"],
			});
			void queryClient.invalidateQueries({
				queryKey: ["collections", variables.toCollectionId, "items"],
			});
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
		},
	});
}

export function useRemoveFromCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			collectionId,
			mediaId,
		}: {
			collectionId: number;
			mediaId: number;
		}) =>
			apiFetch<unknown>(`/collections/${collectionId}/items/${mediaId}`, {
				method: "DELETE",
			}),
		onSuccess: (_data, variables) => {
			void queryClient.invalidateQueries({
				queryKey: ["collections", variables.collectionId, "items"],
			});
		},
	});
}

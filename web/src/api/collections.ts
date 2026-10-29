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

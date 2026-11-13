import {
	queryOptions,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import type { MediaType } from "../core/media";
import {
	addToCollection,
	type BulkMoveCollectionItemsInput,
	bulkMoveCollectionItems,
	bulkRemoveCollectionItems,
	type Collection,
	createCollection,
	deleteCollection,
	fetchCollectionItems,
	fetchCollectionStats,
	fetchCollections,
	moveCollection,
	moveCollectionItem,
	removeFromCollection,
	renameCollection,
} from "./client";

export type { Collection };
export { moveCollection, moveCollectionItem };

function collectionsQueryOptions() {
	return queryOptions({
		queryKey: ["collections"],
		queryFn: () => fetchCollections(),
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
		queryFn: () => fetchCollectionItems(collectionId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useCollectionStats(collectionId: number, enabled = true) {
	return useQuery({
		queryKey: ["collections", collectionId, "stats"],
		queryFn: () => fetchCollectionStats(collectionId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useBulkRemoveCollectionItems(collectionId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (mediaIds: number[]) =>
			bulkRemoveCollectionItems(collectionId, mediaIds),
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
		mutationFn: (input: BulkMoveCollectionItemsInput) =>
			bulkMoveCollectionItems(collectionId, input),
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
			createCollection(name, type),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
		},
	});
}

export function useRenameCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, name }: { id: number; name: string }) =>
			renameCollection(id, name),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
		},
	});
}

export function useDeleteCollection() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => deleteCollection(id),
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
		}) => addToCollection(collectionId, mediaId),
		onSuccess: (_data, variables) => {
			void queryClient.invalidateQueries({
				queryKey: ["collections", variables.collectionId, "items"],
			});
		},
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
		}) => removeFromCollection(collectionId, mediaId),
		onSuccess: (_data, variables) => {
			void queryClient.invalidateQueries({
				queryKey: ["collections", variables.collectionId, "items"],
			});
		},
	});
}

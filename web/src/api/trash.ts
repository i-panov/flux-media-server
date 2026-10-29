import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { mediaSchema } from "../core/media";
import { apiFetch } from "./client";
import { collectionSchema } from "./collections";

const trashSchema = z.object({
	collections: z.array(collectionSchema),
	media: z.array(mediaSchema),
});

function useTrashQuery() {
	return useQuery({
		queryKey: ["trash"],
		queryFn: async () => {
			const body = await apiFetch<unknown>("/trash");
			return trashSchema.parse(body);
		},
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useTrash() {
	return useTrashQuery();
}

export function useTrashActions() {
	const queryClient = useQueryClient();
	const invalidate = () => {
		void queryClient.invalidateQueries({ queryKey: ["trash"] });
		void queryClient.invalidateQueries({ queryKey: ["media"] });
		void queryClient.invalidateQueries({ queryKey: ["collections"] });
	};
	return {
		restoreMedia: useMutation({
			mutationFn: (id: number) =>
				apiFetch<unknown>(`/trash/media/${id}/restore`, { method: "POST" }),
			onSuccess: invalidate,
		}),
		purgeMedia: useMutation({
			mutationFn: (id: number) =>
				apiFetch<unknown>(`/trash/media/${id}`, { method: "DELETE" }),
			onSuccess: invalidate,
		}),
		restoreCollection: useMutation({
			mutationFn: (id: number) =>
				apiFetch<unknown>(`/trash/collections/${id}/restore`, {
					method: "POST",
				}),
			onSuccess: invalidate,
		}),
		purgeCollection: useMutation({
			mutationFn: (id: number) =>
				apiFetch<unknown>(`/trash/collections/${id}`, { method: "DELETE" }),
			onSuccess: invalidate,
		}),
		emptyTrash: useMutation({
			mutationFn: () => apiFetch<unknown>("/trash", { method: "DELETE" }),
			onSuccess: invalidate,
		}),
	};
}

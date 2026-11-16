import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiFetch } from "./client";

export type TagGroup = "format" | "genre" | "mood";
export type TagEntity = "media" | "work" | "franchise";

export interface Tag {
	id: number;
	group: TagGroup;
	slug: string;
	name: string;
	created_at: string;
	updated_at: string;
}

export function useTags(group?: TagGroup) {
	return useQuery({
		queryKey: ["tags", group ?? "all"],
		queryFn: () => apiFetch<Tag[]>(`/tags${group ? `?group=${group}` : ""}`),
	});
}

function invalidateTags(queryClient: ReturnType<typeof useQueryClient>) {
	void queryClient.invalidateQueries({ queryKey: ["tags"] });
}

export function useCreateTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: { group: TagGroup; slug: string; name: string }) =>
			apiFetch<Tag>("/tags", {
				method: "POST",
				body: JSON.stringify(input),
			}),
		onSuccess: () => invalidateTags(queryClient),
	});
}

export function useDeleteTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<void>(`/tags/${id}`, { method: "DELETE" }),
		onSuccess: () => invalidateTags(queryClient),
	});
}

const paths: Record<TagEntity, (id: number) => string> = {
	media: (id) => `/media/${id}/tags`,
	work: (id) => `/works/${id}/tags`,
	franchise: (id) => `/franchises/${id}/tags`,
};

export function useEntityTags(entity: TagEntity, id: number, enabled = true) {
	return useQuery({
		queryKey: ["tags", entity, id],
		queryFn: () => apiFetch<Tag[]>(paths[entity](id)),
		enabled: enabled && id > 0,
	});
}

export function useSetEntityTags(entity: TagEntity, id: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (tagIDs: number[]) =>
			apiFetch<Tag[]>(paths[entity](id), {
				method: "PUT",
				body: JSON.stringify({ tag_ids: tagIDs }),
			}),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["tags", entity, id] });
			void queryClient.invalidateQueries({ queryKey: ["media", id] });
			void queryClient.invalidateQueries({ queryKey: ["works", id] });
			void queryClient.invalidateQueries({ queryKey: ["franchises", id] });
		},
	});
}

import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type TagGroup = "format" | "genre";
export type TagEntity = "media" | "work" | "franchise";

export interface Tag {
	id: number;
	group: TagGroup;
	slug: string;
	name: string;
}

const PATHS: Record<TagEntity, (id: number) => string> = {
	media: (id) => `/media/${id}/tags`,
	work: (id) => `/works/${id}/tags`,
	franchise: (id) => `/franchises/${id}/tags`,
};

export function useTags() {
	return useQuery({
		queryKey: ["tags", "all"],
		queryFn: () => apiFetch<Tag[]>("/tags"),
	});
}

export function useEntityTags(entity: TagEntity, id: number, enabled = true) {
	return useQuery({
		queryKey: ["tags", entity, id],
		queryFn: () => apiFetch<Tag[]>(PATHS[entity](id)),
		enabled: enabled && id > 0,
	});
}

export function useDeleteTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<void>(`/tags/${id}`, { method: "DELETE" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

export function useCreateTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: { group: TagGroup; slug: string; name: string }) =>
			apiFetch<Tag>("/tags", {
				method: "POST",
				body: JSON.stringify(input),
			}),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
		},
	});
}

export function useSetEntityTags(entity: TagEntity, id: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (tagIDs: number[]) =>
			apiFetch<Tag[]>(PATHS[entity](id), {
				method: "PUT",
				body: JSON.stringify({ tag_ids: tagIDs }),
			}),
		onSuccess: (tags) => {
			queryClient.setQueryData(["tags", entity, id], tags);
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

import {
	bulkMediaTags,
	createTag,
	deleteTag,
	fetchEntityTags,
	fetchTags,
	setEntityTags,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type { Tag, TagEntity, TagGroup } from "@flux/shared";

import type { TagEntity, TagGroup } from "@flux/shared";

export function useTags(group?: TagGroup) {
	return useQuery({
		queryKey: ["tags", group ?? "all"],
		queryFn: () => fetchTags(group),
	});
}

function invalidateTags(queryClient: ReturnType<typeof useQueryClient>) {
	void queryClient.invalidateQueries({ queryKey: ["tags"] });
}

export function useCreateTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: createTag,
		onSuccess: () => invalidateTags(queryClient),
	});
}

export function useDeleteTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: deleteTag,
		onSuccess: () => invalidateTags(queryClient),
	});
}

export function useEntityTags(entity: TagEntity, id: number, enabled = true) {
	return useQuery({
		queryKey: ["tags", entity, id],
		queryFn: () => fetchEntityTags(entity, id),
		enabled: enabled && id > 0,
	});
}

export function useSetEntityTags(entity: TagEntity, id: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (tagIDs: number[]) => setEntityTags(entity, id, tagIDs),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["tags", entity, id] });
			void queryClient.invalidateQueries({ queryKey: ["works", id] });
			void queryClient.invalidateQueries({ queryKey: ["franchises", id] });
			if (entity === "media") {
				// Бейджи тегов на карточках в списках и в избранном.
				void queryClient.invalidateQueries({ queryKey: ["media"] });
				void queryClient.invalidateQueries({ queryKey: ["favorites"] });
			}
		},
	});
}

export function useBulkMediaTags() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: bulkMediaTags,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["media"] });
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
		},
	});
}

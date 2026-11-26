import {
	bulkMediaTags,
	createTag,
	deleteTag,
	fetchEntityTags,
	fetchTags,
	setEntityTags,
	type TagEntity,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type { Tag, TagEntity, TagGroup } from "@flux/shared";

export function useTags() {
	return useQuery({ queryKey: ["tags", "all"], queryFn: () => fetchTags() });
}

export function useEntityTags(entity: TagEntity, id: number, enabled = true) {
	return useQuery({
		queryKey: ["tags", entity, id],
		queryFn: () => fetchEntityTags(entity, id),
		enabled: enabled && id > 0,
	});
}

export function useDeleteTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: deleteTag,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
			void queryClient.invalidateQueries({ queryKey: ["works"] });
			void queryClient.invalidateQueries({ queryKey: ["franchises"] });
		},
	});
}

export function useCreateTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: createTag,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
		},
	});
}

export function useSetEntityTags(entity: TagEntity, id: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (tagIDs: number[]) => setEntityTags(entity, id, tagIDs),
		onSuccess: (tags) => {
			queryClient.setQueryData(["tags", entity, id], tags);
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
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

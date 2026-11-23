import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";

export type TagGroup = "format" | "genre";
export type TagEntity = "media" | "work" | "franchise";

const tagSchema = z.object({
	id: z.number(),
	group: z.enum(["format", "genre"]),
	slug: z.string(),
	name: z.string(),
});

const tagListSchema = z.array(tagSchema);

export type Tag = z.infer<typeof tagSchema>;

const PATHS: Record<TagEntity, (id: number) => string> = {
	media: (id) => `/media/${id}/tags`,
	work: (id) => `/works/${id}/tags`,
	franchise: (id) => `/franchises/${id}/tags`,
};

async function fetchTags(): Promise<Tag[]> {
	return tagListSchema.parse(await apiFetch<unknown>("/tags"));
}

export function useTags() {
	return useQuery({ queryKey: ["tags", "all"], queryFn: fetchTags });
}

export function useEntityTags(entity: TagEntity, id: number, enabled = true) {
	return useQuery({
		queryKey: ["tags", entity, id],
		queryFn: async () =>
			tagListSchema.parse((await apiFetch<unknown>(PATHS[entity](id))) ?? []),
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
			void queryClient.invalidateQueries({ queryKey: ["works"] });
			void queryClient.invalidateQueries({ queryKey: ["franchises"] });
		},
	});
}

export function useCreateTag() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async (input: {
			group: TagGroup;
			slug: string;
			name: string;
		}) => {
			const body = await apiFetch<unknown>("/tags", {
				method: "POST",
				body: JSON.stringify(input),
			});
			return tagSchema.parse(body);
		},
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
		},
	});
}

export function useSetEntityTags(entity: TagEntity, id: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async (tagIDs: number[]) => {
			const body = await apiFetch<unknown>(PATHS[entity](id), {
				method: "PUT",
				body: JSON.stringify({ tag_ids: tagIDs }),
			});
			return tagListSchema.parse(body ?? []);
		},
		onSuccess: (tags) => {
			queryClient.setQueryData(["tags", entity, id], tags);
			void queryClient.invalidateQueries({ queryKey: ["tags"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

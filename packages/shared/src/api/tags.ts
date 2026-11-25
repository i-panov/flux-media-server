import { z } from "zod";
import { apiFetch } from "./client";

// Контракт тегов общий для web и mobile: схемы и запросы живут здесь,
// клиенты оставляют только query/mutation-хуки и инвалидации.
export const tagGroupSchema = z.enum(["format", "genre"]);
export type TagGroup = z.infer<typeof tagGroupSchema>;

export type TagEntity = "media" | "work" | "franchise";

export const tagSchema = z.object({
	id: z.number(),
	group: tagGroupSchema,
	slug: z.string(),
	name: z.string(),
	// Старые ответы/мобильный кэш могут не содержать timestamps.
	created_at: z.string().default(""),
	updated_at: z.string().default(""),
});
export type Tag = z.infer<typeof tagSchema>;

const tagListSchema = z.array(tagSchema);

const entityPaths: Record<TagEntity, (id: number) => string> = {
	media: (id) => `/media/${id}/tags`,
	work: (id) => `/works/${id}/tags`,
	franchise: (id) => `/franchises/${id}/tags`,
};

export function tagEntityPath(entity: TagEntity, id: number): string {
	return entityPaths[entity](id);
}

export async function fetchTags(group?: TagGroup): Promise<Tag[]> {
	const suffix = group ? `?group=${group}` : "";
	return tagListSchema.parse(await apiFetch<unknown>(`/tags${suffix}`));
}

export async function createTag(input: {
	group: TagGroup;
	slug: string;
	name: string;
}): Promise<Tag> {
	const body = await apiFetch<unknown>("/tags", {
		method: "POST",
		body: JSON.stringify(input),
	});
	return tagSchema.parse(body);
}

export async function deleteTag(id: number): Promise<void> {
	await apiFetch<unknown>(`/tags/${id}`, { method: "DELETE" });
}

export async function fetchEntityTags(
	entity: TagEntity,
	id: number,
): Promise<Tag[]> {
	return tagListSchema.parse(
		(await apiFetch<unknown>(entityPaths[entity](id))) ?? [],
	);
}

export async function setEntityTags(
	entity: TagEntity,
	id: number,
	tagIDs: number[],
): Promise<Tag[]> {
	const body = await apiFetch<unknown>(entityPaths[entity](id), {
		method: "PUT",
		body: JSON.stringify({ tag_ids: tagIDs }),
	});
	return tagListSchema.parse(body ?? []);
}

export async function bulkMediaTags(input: {
	mediaIDs: number[];
	tagID: number;
	add: boolean;
}): Promise<{ affected: number }> {
	const body = await apiFetch<unknown>("/tags/bulk", {
		method: "POST",
		body: JSON.stringify({
			media_ids: input.mediaIDs,
			tag_id: input.tagID,
			add: input.add,
		}),
	});
	return z.object({ affected: z.number() }).parse(body);
}

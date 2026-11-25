import { z } from "zod";
import { apiFetch } from "./client";

// Глобальный каталог (сериалы, фильмы, сезоны, франшизы): контракт общий
// для web и mobile. Клиенты держат только query/mutation-хуки.
export const workKindSchema = z.enum(["series", "film_series"]);
export type WorkKind = z.infer<typeof workKindSchema>;

export const catalogTagSchema = z.object({
	id: z.number(),
	group: z.string().default(""),
	slug: z.string().default(""),
	name: z.string(),
});
export type CatalogTag = z.infer<typeof catalogTagSchema>;

// В элементах каталога бэкенд отдаёт вложенное медиа; для карточек нужны
// только id/title/duration, остальное не гарантировано.
export const catalogMediaSchema = z.object({
	id: z.number(),
	title: z.string().default(""),
	duration: z.number().default(0),
	thumbnail_url: z.string().default(""),
	cover_url: z.string().default(""),
});
export type CatalogMedia = z.infer<typeof catalogMediaSchema>;

export const catalogItemSchema = z.object({
	id: z.number(),
	work_id: z.number().optional(),
	season_id: z.number().optional(),
	media_id: z.number(),
	position: z.number().default(0),
	episode_number: z.number().optional(),
	media: catalogMediaSchema.optional(),
});
export type CatalogItem = z.infer<typeof catalogItemSchema>;

export const catalogSeasonSchema = z.object({
	id: z.number(),
	work_id: z.number(),
	season_number: z.number(),
	title: z.string().default(""),
	position: z.number().default(0),
	items: z.array(catalogItemSchema).optional(),
	tags: z.array(catalogTagSchema).optional(),
});
export type CatalogSeason = z.infer<typeof catalogSeasonSchema>;

export const catalogWorkSchema = z.object({
	id: z.number(),
	kind: workKindSchema,
	title: z.string(),
	description: z.string().default(""),
	cover_url: z.string().default(""),
	year: z.number().default(0),
	seasons: z.array(catalogSeasonSchema).optional(),
	items: z.array(catalogItemSchema).optional(),
	tags: z.array(catalogTagSchema).optional(),
});
export type CatalogWork = z.infer<typeof catalogWorkSchema>;

export const catalogEntrySchema = z.object({
	id: z.number(),
	franchise_id: z.number(),
	work_id: z.number().optional(),
	media_id: z.number().optional(),
	position: z.number().default(0),
	work: catalogWorkSchema.optional(),
	media: catalogMediaSchema.optional(),
});
export type CatalogEntry = z.infer<typeof catalogEntrySchema>;

export const catalogFranchiseSchema = z.object({
	id: z.number(),
	name: z.string(),
	description: z.string().default(""),
	cover_url: z.string().default(""),
	entries: z.array(catalogEntrySchema).optional(),
	tags: z.array(catalogTagSchema).optional(),
});
export type CatalogFranchise = z.infer<typeof catalogFranchiseSchema>;

export const mediaCatalogContextSchema = z.object({
	work_id: z.number().optional(),
	work_title: z.string().optional(),
	work_kind: workKindSchema.optional(),
	season_id: z.number().optional(),
	season_number: z.number().optional(),
	episode_number: z.number().optional(),
	franchises: z
		.array(z.object({ id: z.number(), name: z.string() }))
		.default([]),
	work_tags: z.array(catalogTagSchema).optional(),
});
export type MediaCatalogContext = z.infer<typeof mediaCatalogContextSchema>;

const workListSchema = z.array(catalogWorkSchema);
const franchiseListSchema = z.array(catalogFranchiseSchema);

function tagQuery(tagIDs: number[]): string {
	return tagIDs.length > 0 ? `?tag_ids=${tagIDs.join(",")}` : "";
}

function write<T>(path: string, method: string, body?: unknown): Promise<T> {
	return apiFetch<T>(path, {
		method,
		body: body === undefined ? undefined : JSON.stringify(body),
	});
}

export async function fetchWorks(
	kind?: WorkKind,
	tagIDs: number[] = [],
): Promise<CatalogWork[]> {
	const params = new URLSearchParams();
	if (kind !== undefined) {
		params.set("kind", kind);
	}
	if (tagIDs.length > 0) {
		params.set("tag_ids", tagIDs.join(","));
	}
	const query = params.toString();
	return workListSchema.parse(
		await apiFetch<unknown>(`/works${query ? `?${query}` : ""}`),
	);
}

export async function fetchWork(id: number): Promise<CatalogWork> {
	return catalogWorkSchema.parse(await apiFetch<unknown>(`/works/${id}`));
}

export async function fetchFranchises(
	tagIDs: number[] = [],
): Promise<CatalogFranchise[]> {
	return franchiseListSchema.parse(
		await apiFetch<unknown>(`/franchises${tagQuery(tagIDs)}`),
	);
}

export async function fetchFranchise(id: number): Promise<CatalogFranchise> {
	return catalogFranchiseSchema.parse(
		await apiFetch<unknown>(`/franchises/${id}`),
	);
}

export async function fetchMediaCatalogContext(
	mediaId: number,
): Promise<MediaCatalogContext> {
	return mediaCatalogContextSchema.parse(
		await apiFetch<unknown>(`/media/${mediaId}/catalog-context`),
	);
}

export interface CreateWorkInput {
	kind: WorkKind;
	title: string;
	description?: string;
	cover_url?: string;
	year?: number;
}

export async function createWork(input: CreateWorkInput): Promise<CatalogWork> {
	return catalogWorkSchema.parse(await write("/works", "POST", input));
}

export async function updateWork(
	id: number,
	patch: Partial<
		Pick<CatalogWork, "title" | "description" | "cover_url" | "year">
	>,
): Promise<CatalogWork> {
	return catalogWorkSchema.parse(await write(`/works/${id}`, "PUT", patch));
}

export async function deleteWork(id: number): Promise<void> {
	await write(`/works/${id}`, "DELETE");
}

export async function createSeason(input: {
	workID: number;
	seasonNumber: number;
	title?: string;
}): Promise<CatalogSeason> {
	return catalogSeasonSchema.parse(
		await write(`/works/${input.workID}/seasons`, "POST", {
			season_number: input.seasonNumber,
			title: input.title ?? "",
		}),
	);
}

export async function deleteSeason(id: number): Promise<void> {
	await write(`/seasons/${id}`, "DELETE");
}

export async function reorderSeasons(
	workID: number,
	ids: number[],
): Promise<void> {
	await write(`/works/${workID}/seasons/order`, "PUT", { season_ids: ids });
}

export async function addEpisode(input: {
	seasonID: number;
	mediaID: number;
	episodeNumber?: number;
}): Promise<CatalogItem> {
	return catalogItemSchema.parse(
		await write(`/seasons/${input.seasonID}/items`, "POST", {
			media_id: input.mediaID,
			episode_number: input.episodeNumber,
		}),
	);
}

export async function removeEpisode(
	seasonID: number,
	mediaID: number,
): Promise<void> {
	await write(`/seasons/${seasonID}/items/${mediaID}`, "DELETE");
}

export async function reorderEpisodes(
	seasonID: number,
	ids: number[],
): Promise<void> {
	await write(`/seasons/${seasonID}/items/order`, "PUT", { item_ids: ids });
}

export async function addFilm(
	workID: number,
	mediaID: number,
): Promise<CatalogItem> {
	return catalogItemSchema.parse(
		await write(`/works/${workID}/items`, "POST", { media_id: mediaID }),
	);
}

export async function removeFilm(
	workID: number,
	mediaID: number,
): Promise<void> {
	await write(`/works/${workID}/items/${mediaID}`, "DELETE");
}

export async function reorderFilms(
	workID: number,
	ids: number[],
): Promise<void> {
	await write(`/works/${workID}/items/order`, "PUT", { item_ids: ids });
}

export interface CreateFranchiseInput {
	name: string;
	description?: string;
	cover_url?: string;
}

export async function createFranchise(
	input: CreateFranchiseInput,
): Promise<CatalogFranchise> {
	return catalogFranchiseSchema.parse(
		await write("/franchises", "POST", input),
	);
}

export async function updateFranchise(
	id: number,
	patch: Partial<Pick<CatalogFranchise, "name" | "description" | "cover_url">>,
): Promise<CatalogFranchise> {
	return catalogFranchiseSchema.parse(
		await write(`/franchises/${id}`, "PUT", patch),
	);
}

export async function deleteFranchise(id: number): Promise<void> {
	await write(`/franchises/${id}`, "DELETE");
}

export async function addFranchiseEntry(input: {
	franchiseID: number;
	workID?: number;
	mediaID?: number;
}): Promise<CatalogEntry> {
	return catalogEntrySchema.parse(
		await write(`/franchises/${input.franchiseID}/entries`, "POST", {
			work_id: input.workID,
			media_id: input.mediaID,
		}),
	);
}

export async function removeFranchiseEntry(
	franchiseID: number,
	entryID: number,
): Promise<void> {
	await write(`/franchises/${franchiseID}/entries/${entryID}`, "DELETE");
}

export async function reorderFranchiseEntries(
	franchiseID: number,
	ids: number[],
): Promise<void> {
	await write(`/franchises/${franchiseID}/entries/order`, "PUT", {
		entry_ids: ids,
	});
}

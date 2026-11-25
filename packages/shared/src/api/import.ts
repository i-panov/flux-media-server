import { z } from "zod";
import { apiFetch } from "./client";

// Импорт сезона/сериала из media-loader: общий контракт web и mobile.
export const importProbeEpisodeSchema = z.object({
	season: z.number(),
	episode: z.number(),
	title: z.string().default(""),
	duration: z.number().default(0),
});
export type ImportProbeEpisode = z.infer<typeof importProbeEpisodeSchema>;

export const importProbeSchema = z.object({
	kind: z.enum(["series", "episode"]),
	series_id: z.string().optional(),
	title: z.string().default(""),
	scope: z.string().default(""),
	seasons: z.array(z.number()).optional(),
	episodes: z.array(importProbeEpisodeSchema).default([]),
	duration: z.number().optional(),
	thumbnail: z.string().optional(),
});
export type ImportProbe = z.infer<typeof importProbeSchema>;

// Статусы приходят строками: новые значения не должны ронять список.
export const importJobSchema = z.object({
	id: z.number(),
	source_url: z.string().default(""),
	scope: z.string().default(""),
	title: z.string().default(""),
	status: z.string(),
	stage: z.string().optional(),
	error: z.string().optional(),
	work_id: z.number().optional(),
	episodes_total: z.number().default(0),
	episodes_done: z.number().default(0),
	episodes_error: z.number().default(0),
});
export type ImportJob = z.infer<typeof importJobSchema>;

export const importEpisodeSchema = z.object({
	id: z.number(),
	season: z.number(),
	episode: z.number(),
	title: z.string().default(""),
	status: z.string(),
	error: z.string().optional(),
	media_id: z.number().optional(),
});
export type ImportEpisode = z.infer<typeof importEpisodeSchema>;

export const importJobDetailSchema = z.object({
	job: importJobSchema,
	episodes: z.array(importEpisodeSchema),
});
export type ImportJobDetail = z.infer<typeof importJobDetailSchema>;

const importJobListSchema = z.array(importJobSchema);

export interface StartImportInput {
	url: string;
	scope: string;
	title: string;
	seriesID?: string;
	episodes: Array<{ season: number; episode: number }>;
}

export async function probeImport(url: string): Promise<ImportProbe> {
	const body = await apiFetch<unknown>("/import/probe", {
		method: "POST",
		body: JSON.stringify({ url }),
	});
	return importProbeSchema.parse(body);
}

export async function startImport(input: StartImportInput): Promise<ImportJob> {
	const body = await apiFetch<unknown>("/import", {
		method: "POST",
		body: JSON.stringify({
			url: input.url,
			scope: input.scope,
			title: input.title,
			series_id: input.seriesID,
			episodes: input.episodes,
		}),
	});
	return importJobSchema.parse(body);
}

export async function fetchImportJobs(): Promise<ImportJob[]> {
	return importJobListSchema.parse(await apiFetch<unknown>("/import"));
}

export async function fetchImportJob(id: number): Promise<ImportJobDetail> {
	return importJobDetailSchema.parse(await apiFetch<unknown>(`/import/${id}`));
}

export async function cancelImport(id: number): Promise<void> {
	await apiFetch<unknown>(`/import/${id}`, { method: "DELETE" });
}

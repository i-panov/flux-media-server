import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";

const probeEpisodeSchema = z.object({
	season: z.number(),
	episode: z.number(),
	title: z.string(),
	duration: z.number(),
});

const probeSchema = z.object({
	kind: z.enum(["series", "episode"]),
	series_id: z.string().optional(),
	title: z.string(),
	scope: z.string(),
	seasons: z.array(z.number()).optional(),
	episodes: z.array(probeEpisodeSchema),
	duration: z.number().optional(),
	thumbnail: z.string().optional(),
});

export type ImportProbe = z.infer<typeof probeSchema>;
export type ImportProbeEpisode = z.infer<typeof probeEpisodeSchema>;

const episodeSchema = z.object({
	id: z.number(),
	season: z.number(),
	episode: z.number(),
	title: z.string(),
	status: z.enum(["queued", "downloading", "done", "error"]),
	error: z.string().optional(),
	media_id: z.number().optional(),
});

const jobSchema = z.object({
	id: z.number(),
	source_url: z.string(),
	scope: z.string(),
	title: z.string(),
	status: z.enum([
		"queued",
		"downloading",
		"importing",
		"done",
		"partial",
		"error",
	]),
	episodes_total: z.number(),
	episodes_done: z.number(),
	episodes_error: z.number(),
	error: z.string().optional(),
});

const jobDetailSchema = z.object({
	job: jobSchema,
	episodes: z.array(episodeSchema),
});

export type ImportJob = z.infer<typeof jobSchema>;
export type ImportEpisode = z.infer<typeof episodeSchema>;
export type ImportJobDetail = z.infer<typeof jobDetailSchema>;

export function useImportProbe() {
	return useMutation({
		mutationFn: async (url: string) => {
			const body = await apiFetch<unknown>("/import/probe", {
				method: "POST",
				body: JSON.stringify({ url }),
			});
			return probeSchema.parse(body);
		},
	});
}

async function startImport(input: {
	url: string;
	scope: "season" | "series";
	title: string;
	seriesID?: string;
	episodes: { season: number; episode: number }[];
}): Promise<ImportJob> {
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
	return jobSchema.parse(body);
}

export function useStartImport() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			url: string;
			scope: "season" | "series";
			title: string;
			seriesID?: string;
			episodes: { season: number; episode: number }[];
		}) => startImport(input),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["import"] });
		},
	});
}

export function useImportJob(id: number | null) {
	const queryClient = useQueryClient();
	return useQuery({
		queryKey: ["import", id],
		queryFn: async () => {
			const detail = jobDetailSchema.parse(
				await apiFetch<unknown>(`/import/${id}`),
			);
			if (
				detail.job.status !== "queued" &&
				detail.job.status !== "downloading" &&
				detail.job.status !== "importing"
			) {
				void queryClient.invalidateQueries({ queryKey: ["works"] });
				void queryClient.invalidateQueries({ queryKey: ["media"] });
			}
			return detail;
		},
		enabled: id !== null && id > 0,
		refetchInterval: (query) => {
			const status = query.state.data?.job.status;
			return status === "queued" ||
				status === "downloading" ||
				status === "importing"
				? 2000
				: false;
		},
	});
}

export function useCancelImport() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<void>(`/import/${id}`, { method: "DELETE" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["import"] });
		},
	});
}

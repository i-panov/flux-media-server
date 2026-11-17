import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiFetch } from "./client";

export interface ImportProbeEpisode {
	season: number;
	episode: number;
	title: string;
	duration: number;
}

export interface ImportProbe {
	kind: "series" | "episode";
	series_id?: string;
	title: string;
	scope: string;
	seasons?: number[];
	episodes: ImportProbeEpisode[];
	duration?: number;
	thumbnail?: string;
}

export interface ImportJob {
	id: number;
	source_url: string;
	scope: string;
	title: string;
	status: string;
	stage?: string;
	error?: string;
	work_id?: number;
	episodes_total: number;
	episodes_done: number;
	episodes_error: number;
}

export interface ImportEpisode {
	id: number;
	season: number;
	episode: number;
	title: string;
	status: string;
	error?: string;
	media_id?: number;
}

export function useImportProbe() {
	return useMutation({
		mutationFn: (url: string) =>
			apiFetch<ImportProbe>("/import/probe", {
				method: "POST",
				body: JSON.stringify({ url }),
			}),
	});
}

export function useStartImport() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			url: string;
			scope: string;
			title: string;
			seriesID?: string;
			episodes: Array<{ season: number; episode: number }>;
		}) =>
			apiFetch<ImportJob>("/import", {
				method: "POST",
				body: JSON.stringify({
					url: input.url,
					scope: input.scope,
					title: input.title,
					series_id: input.seriesID,
					episodes: input.episodes,
				}),
			}),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["import"] });
			void queryClient.invalidateQueries({ queryKey: ["works"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

export function useImportJobs() {
	return useQuery({
		queryKey: ["import", "list"],
		queryFn: () => apiFetch<ImportJob[]>("/import"),
		refetchInterval: (query) =>
			(Array.isArray(query.state.data) ? query.state.data : []).some(
				(job) =>
					job.status !== "done" &&
					job.status !== "error" &&
					job.status !== "partial",
			)
				? 3000
				: false,
	});
}

export function useImportJob(id: number | null) {
	return useQuery({
		queryKey: ["import", id],
		queryFn: () =>
			apiFetch<{ job: ImportJob; episodes: ImportEpisode[] }>(`/import/${id}`),
		enabled: id !== null && id > 0,
		refetchInterval: (query) =>
			query.state.data?.job.status === "downloading" ||
			query.state.data?.job.status === "importing" ||
			query.state.data?.job.status === "queued"
				? 3000
				: false,
	});
}

export function useCancelImport() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<void>(`/import/${id}`, { method: "DELETE" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["import"] });
			void queryClient.invalidateQueries({ queryKey: ["works"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

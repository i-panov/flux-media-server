import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

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

export interface ImportEpisode {
	id: number;
	season: number;
	episode: number;
	title: string;
	status: "queued" | "downloading" | "done" | "error";
	error?: string;
	media_id?: number;
}

export interface ImportJob {
	id: number;
	source_url: string;
	scope: string;
	title: string;
	status: "queued" | "downloading" | "importing" | "done" | "partial" | "error";
	episodes_total: number;
	episodes_done: number;
	episodes_error: number;
	error?: string;
}

export interface ImportJobDetail {
	job: ImportJob;
	episodes: ImportEpisode[];
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
			scope: "season" | "series";
			title: string;
			seriesID?: string;
			episodes: { season: number; episode: number }[];
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
		},
	});
}

export function useImportJob(id: number | null) {
	return useQuery({
		queryKey: ["import", id],
		queryFn: () => apiFetch<ImportJobDetail>(`/import/${id}`),
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

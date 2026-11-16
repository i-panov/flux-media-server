import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type WorkKind = "series" | "film_series";

export interface CatalogItem {
	id: number;
	work_id?: number;
	season_id?: number;
	media_id: number;
	position: number;
	episode_number?: number;
	media?: {
		id: number;
		title: string;
		duration: number;
		thumbnail_url?: string;
		cover_url?: string;
	};
}

export interface CatalogSeason {
	id: number;
	work_id: number;
	season_number: number;
	title: string;
	position: number;
	items?: CatalogItem[];
}

export interface CatalogWork {
	id: number;
	kind: WorkKind;
	title: string;
	description: string;
	cover_url: string;
	year: number;
	seasons?: CatalogSeason[];
	items?: CatalogItem[];
}

export interface CatalogEntry {
	id: number;
	franchise_id: number;
	work_id?: number;
	media_id?: number;
	position: number;
	work?: CatalogWork;
	media?: { id: number; title: string };
}

export interface CatalogFranchise {
	id: number;
	name: string;
	description: string;
	cover_url: string;
	entries?: CatalogEntry[];
}

export function useWorks(kind: WorkKind) {
	return useQuery({
		queryKey: ["works", kind],
		queryFn: () => apiFetch<CatalogWork[]>(`/works?kind=${kind}`),
	});
}

export function useWork(id: number, enabled = true) {
	return useQuery({
		queryKey: ["works", id],
		queryFn: () => apiFetch<CatalogWork>(`/works/${id}`),
		enabled,
	});
}

export function useFranchises() {
	return useQuery({
		queryKey: ["franchises"],
		queryFn: () => apiFetch<CatalogFranchise[]>("/franchises"),
	});
}

export function useFranchise(id: number, enabled = true) {
	return useQuery({
		queryKey: ["franchises", id],
		queryFn: () => apiFetch<CatalogFranchise>(`/franchises/${id}`),
		enabled,
	});
}

function invalidateCatalog(queryClient: ReturnType<typeof useQueryClient>) {
	void queryClient.invalidateQueries({ queryKey: ["works"] });
	void queryClient.invalidateQueries({ queryKey: ["franchises"] });
	void queryClient.invalidateQueries({ queryKey: ["media"] });
}

function write<T>(path: string, method: string, body?: unknown) {
	return apiFetch<T>(path, {
		method,
		body: body === undefined ? undefined : JSON.stringify(body),
	});
}

export function useCreateWork() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: { kind: WorkKind; title: string }) =>
			write<CatalogWork>("/works", "POST", input),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useUpdateWork() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, ...patch }: { id: number; title: string }) =>
			write<CatalogWork>(`/works/${id}`, "PUT", patch),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useCreateSeason() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			workID,
			seasonNumber,
		}: {
			workID: number;
			seasonNumber: number;
		}) =>
			write<CatalogSeason>(`/works/${workID}/seasons`, "POST", {
				season_number: seasonNumber,
				title: "",
			}),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useDeleteSeason() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => write<void>(`/seasons/${id}`, "DELETE"),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useAddEpisode() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			seasonID,
			mediaID,
		}: {
			seasonID: number;
			mediaID: number;
		}) =>
			write<CatalogItem>(`/seasons/${seasonID}/items`, "POST", {
				media_id: mediaID,
			}),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useRemoveEpisode() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			seasonID,
			mediaID,
		}: {
			seasonID: number;
			mediaID: number;
		}) => write<void>(`/seasons/${seasonID}/items/${mediaID}`, "DELETE"),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useReorderEpisodes() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ seasonID, ids }: { seasonID: number; ids: number[] }) =>
			write<void>(`/seasons/${seasonID}/items/order`, "PUT", { item_ids: ids }),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useAddFilm() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ workID, mediaID }: { workID: number; mediaID: number }) =>
			write<CatalogItem>(`/works/${workID}/items`, "POST", {
				media_id: mediaID,
			}),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useRemoveFilm() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ workID, mediaID }: { workID: number; mediaID: number }) =>
			write<void>(`/works/${workID}/items/${mediaID}`, "DELETE"),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useReorderFilms() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ workID, ids }: { workID: number; ids: number[] }) =>
			write<void>(`/works/${workID}/items/order`, "PUT", { item_ids: ids }),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useCreateFranchise() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: { name: string }) =>
			write<CatalogFranchise>("/franchises", "POST", input),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useAddFranchiseEntry() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			franchiseID,
			workID,
			mediaID,
		}: {
			franchiseID: number;
			workID?: number;
			mediaID?: number;
		}) =>
			write<CatalogEntry>(`/franchises/${franchiseID}/entries`, "POST", {
				work_id: workID,
				media_id: mediaID,
			}),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useRemoveFranchiseEntry() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			franchiseID,
			entryID,
		}: {
			franchiseID: number;
			entryID: number;
		}) =>
			write<void>(`/franchises/${franchiseID}/entries/${entryID}`, "DELETE"),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useReorderFranchiseEntries() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			franchiseID,
			ids,
		}: {
			franchiseID: number;
			ids: number[];
		}) =>
			write<void>(`/franchises/${franchiseID}/entries/order`, "PUT", {
				entry_ids: ids,
			}),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useReorderSeasons() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ workID, ids }: { workID: number; ids: number[] }) =>
			write<void>(`/works/${workID}/seasons/order`, "PUT", { season_ids: ids }),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useDeleteWork() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => write<void>(`/works/${id}`, "DELETE"),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useUpdateFranchise() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, name }: { id: number; name: string }) =>
			write<CatalogFranchise>(`/franchises/${id}`, "PUT", { name }),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useDeleteFranchise() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => write<void>(`/franchises/${id}`, "DELETE"),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

import {
	addEpisode,
	addFilm,
	addFranchiseEntry,
	createFranchise,
	createSeason,
	createWork,
	deleteFranchise,
	deleteSeason,
	deleteWork,
	fetchFranchise,
	fetchFranchises,
	fetchMediaCatalogContext,
	fetchWork,
	fetchWorks,
	removeEpisode,
	removeFilm,
	removeFranchiseEntry,
	reorderEpisodes,
	reorderFilms,
	reorderFranchiseEntries,
	reorderSeasons,
	updateFranchise,
	updateWork,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type {
	CatalogEntry,
	CatalogFranchise,
	CatalogItem,
	CatalogSeason,
	CatalogTag,
	CatalogWork,
	MediaCatalogContext,
	WorkKind,
} from "@flux/shared";

import type { CatalogFranchise, CatalogWork, WorkKind } from "@flux/shared";

function invalidateCatalog(queryClient: ReturnType<typeof useQueryClient>) {
	void queryClient.invalidateQueries({ queryKey: ["works"] });
	void queryClient.invalidateQueries({ queryKey: ["franchises"] });
	void queryClient.invalidateQueries({ queryKey: ["media"] });
}

export function useWorks(
	kind?: WorkKind,
	enabled = true,
	tagIDs: number[] = [],
) {
	return useQuery({
		queryKey: ["works", kind ?? "all", tagIDs.join(",")],
		queryFn: () => fetchWorks(kind, tagIDs),
		enabled,
	});
}

export function useWork(id: number, enabled = true) {
	return useQuery({
		queryKey: ["works", id],
		queryFn: () => fetchWork(id),
		enabled: enabled && id > 0,
	});
}

export function useFranchises(tagIDs: number[] = []) {
	return useQuery({
		queryKey: ["franchises", tagIDs.join(",")],
		queryFn: () => fetchFranchises(tagIDs),
	});
}

export function useFranchise(id: number) {
	return useQuery({
		queryKey: ["franchises", id],
		queryFn: () => fetchFranchise(id),
	});
}

export function useCreateWork() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			kind: WorkKind;
			title: string;
			description?: string;
			cover_url?: string;
			year?: number;
		}) => createWork(input),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useUpdateWork() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			id,
			...patch
		}: { id: number } & Partial<
			Pick<CatalogWork, "title" | "description" | "cover_url" | "year">
		>) => updateWork(id, patch),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useDeleteWork() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: deleteWork,
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useCreateSeason() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			workID: number;
			seasonNumber: number;
			title: string;
		}) => createSeason(input),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useDeleteSeason() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: deleteSeason,
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useReorderSeasons() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ workID, ids }: { workID: number; ids: number[] }) =>
			reorderSeasons(workID, ids),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useAddEpisode() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			seasonID: number;
			mediaID: number;
			episodeNumber?: number;
		}) => addEpisode(input),
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
		}) => removeEpisode(seasonID, mediaID),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useReorderEpisodes() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ seasonID, ids }: { seasonID: number; ids: number[] }) =>
			reorderEpisodes(seasonID, ids),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useAddFilm() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ workID, mediaID }: { workID: number; mediaID: number }) =>
			addFilm(workID, mediaID),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useRemoveFilm() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ workID, mediaID }: { workID: number; mediaID: number }) =>
			removeFilm(workID, mediaID),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useReorderFilms() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ workID, ids }: { workID: number; ids: number[] }) =>
			reorderFilms(workID, ids),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useCreateFranchise() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			name: string;
			description?: string;
			cover_url?: string;
		}) => createFranchise(input),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useUpdateFranchise() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({
			id,
			...patch
		}: { id: number } & Partial<
			Pick<CatalogFranchise, "name" | "description" | "cover_url">
		>) => updateFranchise(id, patch),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useDeleteFranchise() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: deleteFranchise,
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useAddFranchiseEntry() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: {
			franchiseID: number;
			workID?: number;
			mediaID?: number;
		}) => addFranchiseEntry(input),
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
		}) => removeFranchiseEntry(franchiseID, entryID),
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
		}) => reorderFranchiseEntries(franchiseID, ids),
		onSuccess: () => invalidateCatalog(queryClient),
	});
}

export function useMediaCatalogContext(mediaId: number, enabled = true) {
	return useQuery({
		queryKey: ["media", mediaId, "catalog-context"],
		queryFn: () => fetchMediaCatalogContext(mediaId),
		enabled: enabled && mediaId > 0,
	});
}

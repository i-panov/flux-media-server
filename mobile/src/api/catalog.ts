import { apiFetch } from "@flux/shared";
import { useQuery } from "@tanstack/react-query";

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

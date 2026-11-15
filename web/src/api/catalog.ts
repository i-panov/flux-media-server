import { useQuery } from "@tanstack/react-query";
import type { Media } from "../core/media";
import { apiFetch } from "./client";

export type WorkKind = "series" | "film_series";

interface CatalogItem {
	id: number;
	work_id?: number;
	season_id?: number;
	media_id: number;
	position: number;
	episode_number?: number;
	media?: Media;
}

interface CatalogSeason {
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

interface CatalogEntry {
	id: number;
	franchise_id: number;
	work_id?: number;
	media_id?: number;
	position: number;
	work?: CatalogWork;
	media?: Media;
}

export interface CatalogFranchise {
	id: number;
	name: string;
	description: string;
	cover_url: string;
	entries?: CatalogEntry[];
}

export function useWorks(kind?: WorkKind) {
	return useQuery({
		queryKey: ["works", kind ?? "all"],
		queryFn: () =>
			apiFetch<CatalogWork[]>(`/works${kind ? `?kind=${kind}` : ""}`),
	});
}

export function useWork(id: number) {
	return useQuery({
		queryKey: ["works", id],
		queryFn: () => apiFetch<CatalogWork>(`/works/${id}`),
	});
}

export function useFranchises() {
	return useQuery({
		queryKey: ["franchises"],
		queryFn: () => apiFetch<CatalogFranchise[]>("/franchises"),
	});
}

export function useFranchise(id: number) {
	return useQuery({
		queryKey: ["franchises", id],
		queryFn: () => apiFetch<CatalogFranchise>(`/franchises/${id}`),
	});
}

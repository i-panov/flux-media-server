import type { CatalogWork } from "../api/catalog";

const NUMERIC_ID = /^[1-9]\d*$/;

export function parseCatalogID(raw: string | undefined): number | null {
	if (raw === undefined || !NUMERIC_ID.test(raw)) return null;
	const value = Number(raw);
	return Number.isSafeInteger(value) ? value : null;
}

export function mergeWorks(
	series: readonly CatalogWork[] | undefined,
	films: readonly CatalogWork[] | undefined,
): CatalogWork[] {
	return [...(series ?? []), ...(films ?? [])];
}

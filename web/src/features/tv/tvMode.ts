export const TV_MODE_STORAGE_KEY = "flux.tv-mode";
export const TV_MODE_SEARCH_PARAM = "tv";

export function parseTVSearchParam(search: string): boolean | null {
	const normalized = search.startsWith("?") ? search.slice(1) : search;
	const params = new URLSearchParams(normalized);
	if (!params.has(TV_MODE_SEARCH_PARAM)) {
		return null;
	}
	return params.get(TV_MODE_SEARCH_PARAM) === "1";
}

export function readStoredTVMode(): boolean {
	try {
		return window.localStorage.getItem(TV_MODE_STORAGE_KEY) === "1";
	} catch {
		return false;
	}
}

export function writeStoredTVMode(enabled: boolean): void {
	try {
		window.localStorage.setItem(TV_MODE_STORAGE_KEY, enabled ? "1" : "0");
	} catch {
		// Приватный режим или отключённое хранилище: режим живёт до перезагрузки.
	}
}

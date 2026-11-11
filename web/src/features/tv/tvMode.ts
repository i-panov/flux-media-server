export const TV_MODE_STORAGE_KEY = "flux.tv-mode";
const TV_HINT_STORAGE_KEY = "flux.tv-hint-dismissed";
const TV_MODE_SEARCH_PARAM = "tv";

export function parseTVSearchParam(search: string): boolean | null {
	const normalized = search.startsWith("?") ? search.slice(1) : search;
	const params = new URLSearchParams(normalized);
	if (!params.has(TV_MODE_SEARCH_PARAM)) {
		return null;
	}
	return params.get(TV_MODE_SEARCH_PARAM) === "1";
}

// null — пользователь ещё не делал явного выбора: автоопределение профиля
// может включить ТВ само. "0" — явный отказ, он старше автоопределения.
export function readStoredTVModeOverride(): boolean | null {
	try {
		const value = window.localStorage.getItem(TV_MODE_STORAGE_KEY);
		if (value === "1") {
			return true;
		}
		if (value === "0") {
			return false;
		}
		return null;
	} catch {
		return null;
	}
}

export function readStoredTVMode(): boolean {
	return readStoredTVModeOverride() === true;
}

export function writeStoredTVMode(enabled: boolean): void {
	try {
		window.localStorage.setItem(TV_MODE_STORAGE_KEY, enabled ? "1" : "0");
	} catch {
		// Приватный режим или отключённое хранилище: режим живёт до перезагрузки.
	}
}

export function readTVHintDismissed(): boolean {
	try {
		return window.localStorage.getItem(TV_HINT_STORAGE_KEY) === "1";
	} catch {
		return false;
	}
}

export function writeTVHintDismissed(dismissed: boolean): void {
	try {
		window.localStorage.setItem(TV_HINT_STORAGE_KEY, dismissed ? "1" : "0");
	} catch {
		// Подсказка не критична: без хранилища она появится снова.
	}
}

import {
	type ClientProfile,
	detectBrowserClientProfile,
	resolveTVMode,
} from "./clientProfile";
import {
	parseTVSearchParam,
	readStoredTVModeOverride,
	writeStoredTVMode,
} from "./tvMode";

// Маршруты записи. В ТВ они недоступны и на уровне навигации, и на уровне
// URL: guard отвечает за прямой заход/закладку, а не только за скрытые кнопки.
const TV_READ_ONLY_PATHS: ReadonlySet<string> = new Set([
	"/upload",
	"/trash",
	"/admin",
	"/memes",
]);

// Раздел мемов вместе с деталями: на ТВ не показываем.
const TV_READ_ONLY_PREFIXES = ["/memes/"];

function normalizePathname(pathname: string): string {
	if (pathname === "") {
		return "/";
	}
	return pathname.length > 1 && pathname.endsWith("/")
		? pathname.slice(0, -1)
		: pathname;
}

export function isTVReadOnlyPath(pathname: string): boolean {
	const normalized = normalizePathname(pathname);
	return (
		TV_READ_ONLY_PATHS.has(normalized) ||
		TV_READ_ONLY_PREFIXES.some((prefix) => normalized.startsWith(prefix))
	);
}

export function tvRouteRedirectTarget(pathname: string): "/" | "/video" {
	return normalizePathname(pathname).startsWith("/memes") ? "/video" : "/";
}

// Тот же приоритет, что и у TVModeContext: URL, сохранённый выбор,
// автоопределение. Ручной тумблер всегда пишет localStorage, поэтому
// guard видит его до монтирования React-дерева.
export function isTVModeAtLocation(
	search: string,
	profile: ClientProfile = detectBrowserClientProfile(),
): boolean {
	return resolveTVMode(
		parseTVSearchParam(search),
		readStoredTVModeOverride(),
		profile,
	);
}

export function shouldBlockTVRoute(
	pathname: string,
	search: string,
	profile?: ClientProfile,
): boolean {
	const blocked =
		isTVReadOnlyPath(pathname) &&
		isTVModeAtLocation(search, profile ?? detectBrowserClientProfile());
	// Guard срабатывает до монтирования TVModeContext, поэтому `?tv=1` из
	// заблокированного URL сам в localStorage не попадёт. Сохраняем режим
	// здесь: после redirect и reload пользователь остаётся в ТВ-профиле.
	if (blocked) {
		writeStoredTVMode(true);
	}
	return blocked;
}

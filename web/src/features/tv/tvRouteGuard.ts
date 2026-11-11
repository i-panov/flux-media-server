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
]);

function normalizePathname(pathname: string): string {
	if (pathname === "") {
		return "/";
	}
	return pathname.length > 1 && pathname.endsWith("/")
		? pathname.slice(0, -1)
		: pathname;
}

export function isTVReadOnlyPath(pathname: string): boolean {
	return TV_READ_ONLY_PATHS.has(normalizePathname(pathname));
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

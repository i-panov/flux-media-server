import { useRouter, useRouterState } from "@tanstack/react-router";
import {
	createContext,
	type ReactNode,
	useCallback,
	useEffect,
	useMemo,
	useState,
} from "react";
import { type ClientCapabilities, capabilitiesForTVMode } from "./capabilities";
import {
	type ClientProfile,
	detectBrowserClientProfile,
	resolveTVMode,
} from "./clientProfile";
import {
	hrefWithoutTVSearchParam,
	parseTVSearchParam,
	readStoredTVModeOverride,
	readTVHintDismissed,
	writeStoredTVMode,
	writeTVHintDismissed,
} from "./tvMode";

export interface TVModeState {
	tvMode: boolean;
	setTVMode: (enabled: boolean) => void;
	profile: ClientProfile;
	capabilities: ClientCapabilities;
	// Неоднозначный клиент: обычный режим, но показываем подсказку.
	showTVHint: boolean;
	dismissTVHint: () => void;
}

export const TVModeContext = createContext<TVModeState | null>(null);

type ReplaceHistory = (href: string) => void;

// Запасной путь вне RouterProvider (тесты, сторибуки): обновляем адрес
// напрямую, чтобы устаревший ?tv=1 не пережил reload.
function replaceBrowserHistory(href: string): void {
	try {
		window.history.replaceState(window.history.state, "", href);
	} catch {
		// Без History API адрес не обновить: режим всё равно живёт в localStorage.
	}
}

// Внутреннее состояние ТВ-режима: ручной тумблер, иначе `?tv=1` в URL,
// иначе сохранённый явный выбор, иначе автоопределение профиля.
// URL-параметр при заходе сохраняется, дальше флаг живёт в localStorage.
// Тумблер старше параметра, чтобы выключение на странице с `?tv=1`
// в адресе срабатывало сразу, а не после первого перехода.
export function useTVModeState(
	replaceHistory: ReplaceHistory = replaceBrowserHistory,
): TVModeState {
	const search = useRouterState({
		select: (state) => state.location.searchStr,
	});
	const [profile] = useState(detectBrowserClientProfile);
	const [manual, setManual] = useState<boolean | null>(null);
	const [hintDismissed, setHintDismissed] = useState(readTVHintDismissed);
	const param = parseTVSearchParam(search);
	const stored = readStoredTVModeOverride();

	// URL-параметр переносим в localStorage только пока пользователь не
	// трогал тумблер. Иначе выключение на странице с `?tv=1` тут же
	// перезаписывалось бы обратно в "1".
	useEffect(() => {
		if (manual !== null) {
			return;
		}
		if (param !== null && stored !== param) {
			writeStoredTVMode(param);
		}
	}, [param, stored, manual]);

	const tvMode = manual ?? resolveTVMode(param, stored, profile);

	const setTVMode = useCallback(
		(enabled: boolean) => {
			writeStoredTVMode(enabled);
			setManual(enabled);
			// ?tv=1/?tv=0 — принудительный режим на один заход. После явного
			// выбора в настройках он устарел: убираем параметр, чтобы reload
			// не перебил сохранённое значение и в адресе не осталось "1".
			if (param !== null && param !== enabled) {
				const href = hrefWithoutTVSearchParam();
				if (href !== null) {
					replaceHistory(href);
				}
			}
		},
		[param, replaceHistory],
	);

	const dismissTVHint = useCallback(() => {
		writeTVHintDismissed(true);
		setHintDismissed(true);
	}, []);

	return useMemo(
		() => ({
			tvMode,
			setTVMode,
			profile,
			capabilities: capabilitiesForTVMode(tvMode),
			showTVHint: !tvMode && profile.ambiguous && !hintDismissed,
			dismissTVHint,
		}),
		[tvMode, setTVMode, profile, hintDismissed, dismissTVHint],
	);
}

// Общий стор ТВ-режима. Монтируется один раз в __root.tsx поверх TVSpatialRoot
// и остального дерева, чтобы тумблер в Настройках доходил до TVSpatialRoot
// без навигации. Подписка только на строку поиска роутера, чтобы не
// ререндерить по каждому переходу.
export function TVModeProvider({ children }: { children: ReactNode }) {
	const router = useRouter();
	const replaceHistory = useCallback(
		(href: string) => {
			router.history.replace(href);
		},
		[router],
	);
	const value = useTVModeState(replaceHistory);
	return (
		<TVModeContext.Provider value={value}>{children}</TVModeContext.Provider>
	);
}

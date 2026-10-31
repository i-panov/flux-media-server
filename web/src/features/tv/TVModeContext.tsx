import { useRouterState } from "@tanstack/react-router";
import {
	createContext,
	type ReactNode,
	useCallback,
	useEffect,
	useMemo,
	useState,
} from "react";
import {
	parseTVSearchParam,
	readStoredTVMode,
	writeStoredTVMode,
} from "./tvMode";

export interface TVModeState {
	tvMode: boolean;
	setTVMode: (enabled: boolean) => void;
}

export const TVModeContext = createContext<TVModeState | null>(null);

// Внутреннее состояние ТВ-режима: ручной тумблер, иначе `?tv=1` в URL,
// иначе сохранённый флаг. URL-параметр при заходе сохраняется, дальше флаг
// живёт в localStorage. Тумблер старше параметра, чтобы выключение на странице
// с `?tv=1` в адресе срабатывало сразу, а не после первого перехода.
export function useTVModeState(): TVModeState {
	const search = useRouterState({
		select: (state) => state.location.searchStr,
	});
	const [manual, setManual] = useState<boolean | null>(null);
	const param = parseTVSearchParam(search);

	useEffect(() => {
		if (param !== null && readStoredTVMode() !== param) {
			writeStoredTVMode(param);
		}
	}, [param]);

	const tvMode = manual ?? param ?? readStoredTVMode();

	const setTVMode = useCallback((enabled: boolean) => {
		writeStoredTVMode(enabled);
		setManual(enabled);
	}, []);

	return useMemo(() => ({ tvMode, setTVMode }), [tvMode, setTVMode]);
}

// Общий стор ТВ-режима. Монтируется один раз в __root.tsx поверх TVSpatialRoot
// и остального дерева, чтобы тумблер в Настройках доходил до TVSpatialRoot
// без навигации. Подписка только на строку поиска роутера, чтобы не
// ререндерить по каждому переходу.
export function TVModeProvider({ children }: { children: ReactNode }) {
	const value = useTVModeState();
	return (
		<TVModeContext.Provider value={value}>{children}</TVModeContext.Provider>
	);
}

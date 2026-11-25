import { useContext } from "react";
import { capabilitiesForTVMode } from "./capabilities";
import type { ClientProfile } from "./clientProfile";
import { TVModeContext, type TVModeState } from "./TVModeContext";

export type { TVModeState } from "./TVModeContext";

// Вне TVModeProvider (тесты, сторибуки) — обычный режим без побочных
// эффектов. Раньше здесь запускался полноценный fallback-хук с подпиской
// на роутер, matchMedia и localStorage: он выполнялся на КАЖДЫЙ
// focusable-элемент, то есть десятки раз на страницу.
const FALLBACK_PROFILE: ClientProfile = {
	kind: "desktop",
	isTV: false,
	isMobile: false,
	ambiguous: false,
	score: 0,
	signals: [],
};

const FALLBACK_STATE: TVModeState = {
	tvMode: false,
	setTVMode: () => {},
	profile: FALLBACK_PROFILE,
	capabilities: capabilitiesForTVMode(false),
	showTVHint: false,
	dismissTVHint: () => {},
};

export function useTVMode(): TVModeState {
	return useContext(TVModeContext) ?? FALLBACK_STATE;
}

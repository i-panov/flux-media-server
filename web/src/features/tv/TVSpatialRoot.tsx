import {
	destroy,
	init,
	setFocus,
} from "@noriginmedia/norigin-spatial-navigation";
import { useRouterState } from "@tanstack/react-router";
import { useEffect } from "react";
import { useTVBackNavigation } from "./tvBack";
import { useTVMode } from "./useTVMode";

const TV_ROOT_CLASS = "tv-mode";
const ROUTE_FOCUS_DELAY = 120;

// Смена роута в ТВ-режиме: spatial-фокус на первую секцию страницы
// (setFocus спускается к первому ребёнку), иначе пульт висит в пустоте:
// spatial глушит нативный Enter, и без фокуса ОК ничего не делает.
// В обычном режиме — ничего: ни фокуса, ни скролла.
function useTVRouteFocus(tvMode: boolean): void {
	const pathname = useRouterState({
		select: (state) => state.location.pathname,
	});

	// pathname в deps — триггер перезапуска фокуса при смене роута.
	// biome-ignore lint/correctness/useExhaustiveDependencies: pathname в теле не читается.
	useEffect(() => {
		if (!tvMode) {
			return;
		}
		const timer = setTimeout(() => {
			const section = document.querySelector("main [data-tv-focus-key]");
			const focusKey = section?.getAttribute("data-tv-focus-key");
			if (focusKey !== null && focusKey !== undefined && focusKey !== "") {
				void setFocus(focusKey);
				return;
			}
			document.querySelector("main")?.focus({ preventScroll: true });
		}, ROUTE_FOCUS_DELAY);
		return () => {
			clearTimeout(timer);
		};
	}, [pathname, tvMode]);
}

// Корень ТВ-режима: живёт рядом с провайдерами в __root.tsx. В обычном режиме
// ничего не делает.
export function TVSpatialRoot() {
	const { tvMode } = useTVMode();
	useTVBackNavigation(tvMode);
	useTVRouteFocus(tvMode);

	useEffect(() => {
		setTVRootClass(tvMode);
		if (!tvMode) {
			return;
		}
		// shouldFocusDOMNode: фокус уходит в реальные DOM-узлы, поэтому CSS
		// `.tv-mode :focus` подсвечивает текущий элемент, а проверки
		// document.activeElement в e2e видят spatial-фокус.
		init({ shouldFocusDOMNode: true });
		return () => {
			destroy();
			setTVRootClass(false);
		};
	}, [tvMode]);

	return null;
}

function setTVRootClass(enabled: boolean): void {
	document.getElementById("root")?.classList.toggle(TV_ROOT_CLASS, enabled);
}

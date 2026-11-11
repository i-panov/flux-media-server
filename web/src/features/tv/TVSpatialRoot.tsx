import { destroy, init } from "@noriginmedia/norigin-spatial-navigation";
import { useEffect } from "react";
import { useTVBackNavigation } from "./tvBack";
import { useTVRouteFocus } from "./tvRouteFocus";
import { useTVMode } from "./useTVMode";

const TV_ROOT_CLASS = "tv-mode";

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

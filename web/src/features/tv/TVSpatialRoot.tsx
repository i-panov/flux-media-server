import { init, pause, resume } from "@noriginmedia/norigin-spatial-navigation";
import { useEffect } from "react";
import { useTVBackNavigation } from "./tvBack";
import { useTVRouteFocus } from "./tvRouteFocus";
import { useTVMode } from "./useTVMode";

const TV_ROOT_CLASS = "tv-mode";

// Корень ТВ-режима: живёт рядом с провайдерами в __root.tsx. В обычном режиме
// навигацию не перехватывает, но и не сносит реестр focusable-компонентов.
export function TVSpatialRoot() {
	const { tvMode } = useTVMode();
	useTVBackNavigation(tvMode);
	useTVRouteFocus(tvMode);

	useEffect(() => {
		setTVRootClass(tvMode);
		if (tvMode) {
			// shouldFocusDOMNode: фокус уходит в реальные DOM-узлы, поэтому CSS
			// `.tv-mode :focus` подсвечивает текущий элемент, а проверки
			// document.activeElement в e2e видят spatial-фокус.
			// init() идемпотентен: повторное включение не сбрасывает реестр.
			init({ shouldFocusDOMNode: true });
			resume();
		} else {
			// destroy() обнуляет focusableComponents, а useFocusable
			// регистрируется только при монтировании — после off→on
			// навигация оставалась пустой. Поэтому выключение лишь ставит
			// навигацию на паузу; включение возвращает её на место.
			pause();
		}
		return () => {
			// На размонтировании/смене режима гасим обработчики, но реестр
			// не трогаем: StrictMode прогоняет setup→cleanup→setup, а
			// повторный init() должен увидеть те же focusable-узлы.
			pause();
			setTVRootClass(false);
		};
	}, [tvMode]);

	return null;
}

function setTVRootClass(enabled: boolean): void {
	document.getElementById("root")?.classList.toggle(TV_ROOT_CLASS, enabled);
}

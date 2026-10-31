import { useContext } from "react";
import {
	TVModeContext,
	type TVModeState,
	useTVModeState,
} from "./TVModeContext";

export type { TVModeState } from "./TVModeContext";

// Читает общий стор из TVModeProvider. Вне провайдера (тесты, сторибуки)
// работает на собственном состоянии с тем же приоритетом:
// ручной тумблер, иначе `?tv=1` в URL, иначе сохранённый флаг.
// Запасной хук вызывается всегда, чтобы не ломать порядок хуков.
export function useTVMode(): TVModeState {
	const context = useContext(TVModeContext);
	const fallback = useTVModeState();
	return context ?? fallback;
}

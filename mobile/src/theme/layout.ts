import { spacing } from "./tokens";

// Горизонтальные/общие отступы экрана: один источник для Screen и для
// расчёта ширины карточек каталога.
export function screenPadding(wide: boolean): number {
	return wide ? spacing.xl : spacing.lg;
}

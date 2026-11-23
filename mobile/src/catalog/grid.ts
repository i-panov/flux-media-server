import { screenPadding } from "../theme/layout";

// Колонки каталога по ширине окна: телефон/планшет/ТВ.
export function catalogColumns(width: number): number {
	if (width >= 900) return 4;
	if (width >= 600) return 3;
	return 2;
}

// Отступы экрана: единственный источник — theme/layout, чтобы сетка не
// разошлась с Screen.
export function catalogPadding(wide: boolean): number {
	return screenPadding(wide);
}

// Ширина карточки без «растягивания» последнего ряда: фиксируем её от
// доступной ширины, а не через flex.
export function catalogCardWidth(
	width: number,
	columns: number,
	padding: number,
	gap: number,
): number {
	const usable = width - padding * 2 - gap * (columns - 1);
	const card = Math.floor(usable / columns);
	return Math.max(card, 0);
}

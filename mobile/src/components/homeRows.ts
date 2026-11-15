// Сколько карточек держим в горизонтальном ряду: остальное доступно через
// «Продолжить»/избранное на соответствующих экранах.
export const HOME_ROW_LIMIT = 20;

// Пустые ряды не рендерятся вовсе, а не показывают заголовок без карточек.
export function isRowVisible(
	items: readonly unknown[] | null | undefined,
): boolean {
	return items !== null && items !== undefined && items.length > 0;
}

export function clampProgress(value: number): number {
	if (Number.isNaN(value)) {
		return 0;
	}
	return Math.min(1, Math.max(0, value));
}

// Позиция из записи прогресса; длительность прогресса точнее карточки
// (её пишет плеер), но для старых записей берём duration медиа.
export function continueProgressRatio(
	entry: { position: number; duration: number },
	fallbackDuration = 0,
): number {
	const total = entry.duration > 0 ? entry.duration : fallbackDuration;
	if (total <= 0) {
		return 0;
	}
	return clampProgress(entry.position / total);
}

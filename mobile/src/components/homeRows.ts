import type { Collection } from "@flux/shared";

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

// Корневые коллекции выбранного типа: ребёнок, чей родитель есть в списке,
// в ряд не попадает. Коллекция с отсутствующим родителем считается корнем,
// иначе она потерялась бы из UI при удалении папки-родителя.
export function rootCollections(
	collections: readonly Collection[],
	type: string,
): Collection[] {
	const ids = new Set(collections.map((collection) => collection.id));
	return collections.filter(
		(collection) =>
			collection.type === type &&
			(collection.parent_id === null ||
				collection.parent_id === undefined ||
				!ids.has(collection.parent_id)),
	);
}

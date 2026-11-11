import type { Media } from "@flux/shared";

// Основной список без избранного: оно уже показано отдельным рядом выше.
// undefined означает «избранное ещё не загружено» — в этом случае список
// не фильтруем, иначе на первом кадре пропали бы все избранные карточки.
export function excludeMediaIds(
	items: readonly Media[],
	excludedIds: ReadonlySet<number> | undefined,
): Media[] {
	if (excludedIds === undefined || excludedIds.size === 0) {
		return [...items];
	}
	return items.filter((item) => !excludedIds.has(item.id));
}

interface EmptyBecauseOfExclusionsInput {
	/** Идёт поиск: избранное в результатах не исключается. */
	searching: boolean;
	allCount: number;
	visibleCount: number;
	excludedCount: number;
}

// Отличает «библиотека пуста» от «все элементы уже показаны в избранном
// выше». Второй случай нейтрален: это не пустая библиотека и не результат
// поиска, поэтому CTA «загрузите файлы» здесь был бы неверным.
export function isEmptyBecauseOfExclusions({
	searching,
	allCount,
	visibleCount,
	excludedCount,
}: EmptyBecauseOfExclusionsInput): boolean {
	return !searching && allCount > 0 && visibleCount === 0 && excludedCount > 0;
}

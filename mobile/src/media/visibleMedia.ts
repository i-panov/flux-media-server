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

// Чистая логика выбора состояния сетки: её легко проверить в Node,
// не поднимая React Native. Ошибка при непустом списке не скрывает
// карточки — retry показывается футером пагинации.
export type MediaGridState = "loading" | "error" | "empty" | "content";

interface MediaGridStateInput {
	isPending: boolean;
	isError: boolean;
	itemCount: number;
}

export function resolveMediaGridState({
	isPending,
	isError,
	itemCount,
}: MediaGridStateInput): MediaGridState {
	if (isPending) {
		return "loading";
	}
	if (isError && itemCount === 0) {
		return "error";
	}
	if (itemCount === 0) {
		return "empty";
	}
	return "content";
}

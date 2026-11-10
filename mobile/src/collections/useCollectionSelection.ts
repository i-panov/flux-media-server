import { useMemo, useState } from "react";
import { pruneSelection, toggleSelection } from "./tree";

export interface CollectionSelection {
	selecting: boolean;
	selected: ReadonlySet<number>;
	/** Войти в режим выбора без выбора элемента (кнопка «Выбрать»). */
	begin: () => void;
	/** Войти в режим выбора и добавить элемент (долгое нажатие). */
	start: (mediaId: number) => void;
	/** Переключить элемент; выход из режима при пустом выборе. */
	toggle: (mediaId: number) => void;
	/** Снять выбор и выйти из режима. */
	exit: () => void;
}

// availableIds — текущие элементы коллекции. Если список обновился
// (например, элементы убрали с другого устройства), устаревшие id не
// попадают в счётчик и в bulk-запрос.
export function useCollectionSelection(
	availableIds: ReadonlySet<number>,
): CollectionSelection {
	const [selecting, setSelecting] = useState(false);
	const [rawSelected, setRawSelected] = useState<Set<number>>(() => new Set());
	const selected = useMemo(
		() => pruneSelection(rawSelected, availableIds),
		[rawSelected, availableIds],
	);

	const exit = () => {
		setSelecting(false);
		setRawSelected(new Set());
	};

	const toggle = (mediaId: number) => {
		const next = toggleSelection(selected, mediaId);
		setRawSelected(next);
		if (next.size === 0) {
			setSelecting(false);
		}
	};

	const begin = () => {
		setRawSelected(selected);
		setSelecting(true);
	};

	const start = (mediaId: number) => {
		setSelecting(true);
		setRawSelected((previous) => {
			const pruned = pruneSelection(previous, availableIds);
			return pruned.has(mediaId) ? pruned : toggleSelection(pruned, mediaId);
		});
	};

	return { selecting, selected, begin, start, toggle, exit };
}

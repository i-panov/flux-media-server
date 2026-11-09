import { useEffect, useState } from "react";

// Выбор элементов коллекции. Сброс привязан к collectionId: переход
// к другой коллекции не должен тащить id старой.
export function useCollectionSelection(collectionId: number) {
	const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
	const [bulkMoveOpened, setBulkMoveOpened] = useState(false);
	// biome-ignore lint/correctness/useExhaustiveDependencies: collectionId — триггер сброса.
	useEffect(() => {
		setSelectedIds(new Set());
		setBulkMoveOpened(false);
	}, [collectionId]);
	return {
		selectedIds,
		setSelectedIds,
		bulkMoveOpened,
		setBulkMoveOpened,
	};
}

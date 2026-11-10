import type { Collection, MediaType } from "@flux/shared";

// Плоский узел дерева: коллекция и её глубина для отступа/шеврона.
export interface CollectionTreeNode {
	readonly collection: Collection;
	readonly depth: number;
}

const MEDIA_TYPES: readonly MediaType[] = ["video", "audio", "image"];

// Тип коллекции приходит строкой (backend исторически допускает любое
// значение); для UI сужаем до известных типов и иначе отдаём null.
export function asMediaType(value: string): MediaType | null {
	return MEDIA_TYPES.includes(value as MediaType) ? (value as MediaType) : null;
}

function parentIdOf(collection: Collection): number | null {
	return collection.parent_id ?? null;
}

// Прямые дети в исходном порядке списка. Тип опционален: библиотека
// показывает всё дерево, экран коллекции — только свой тип.
export function collectionChildren(
	collections: readonly Collection[],
	parentId: number,
	type?: string,
): Collection[] {
	return collections.filter(
		(collection) =>
			parentIdOf(collection) === parentId &&
			(type === undefined || collection.type === type),
	);
}

// Корни — коллекции без родителя или с родителем, которого нет в списке.
// Второй случай важен: после удаления папки-родителя её дети не должны
// пропасть из интерфейса.
export function collectionRoots(
	collections: readonly Collection[],
	type?: string,
): Collection[] {
	const ids = new Set(collections.map((collection) => collection.id));
	return collections.filter(
		(collection) =>
			(type === undefined || collection.type === type) &&
			(parentIdOf(collection) === null ||
				!ids.has(parentIdOf(collection) as number)),
	);
}

// Id самой коллекции и всех потомков: переезд под них замкнул бы цикл.
// Обход защищён от циклов в данных, чтобы зависший сервер не повесил UI.
export function collectionDescendantIds(
	collections: readonly Collection[],
	rootId: number,
): Set<number> {
	const excluded = new Set<number>([rootId]);
	const childrenByParent = new Map<number, number[]>();
	for (const collection of collections) {
		const parentId = parentIdOf(collection);
		if (parentId === null) {
			continue;
		}
		const list = childrenByParent.get(parentId) ?? [];
		list.push(collection.id);
		childrenByParent.set(parentId, list);
	}
	const stack = [rootId];
	while (stack.length > 0) {
		const current = stack.pop();
		if (current === undefined) {
			continue;
		}
		for (const child of childrenByParent.get(current) ?? []) {
			if (excluded.has(child)) {
				continue;
			}
			excluded.add(child);
			stack.push(child);
		}
	}
	return excluded;
}

// Путь от корня до коллекции включительно. При битой цепочке (родитель
// удалён) возвращает то, что удалось собрать; цикл обрывается visited.
export function collectionBreadcrumbs(
	collections: readonly Collection[],
	collectionId: number,
): Collection[] {
	const byId = new Map(
		collections.map((collection) => [collection.id, collection]),
	);
	const chain: Collection[] = [];
	const visited = new Set<number>();
	let current = byId.get(collectionId);
	while (current !== undefined && !visited.has(current.id)) {
		visited.add(current.id);
		chain.unshift(current);
		const parentId = parentIdOf(current);
		current = parentId === null ? undefined : byId.get(parentId);
	}
	return chain;
}

// Развёрнутое в плоский список дерево. Свёрнутые узлы скрывают своих
// детей, поэтому экран хранит только collapsed-id, а новые коллекции по
// умолчанию видны. Недостижимые из корней узлы (цикл без корня) всё равно
// показываем как корни, чтобы данные не исчезли.
export function flattenCollectionTree(
	collections: readonly Collection[],
	type: string | undefined,
	collapsed: ReadonlySet<number>,
): CollectionTreeNode[] {
	const nodes: CollectionTreeNode[] = [];
	const visited = new Set<number>();

	// Скрытое поддерево помечаем visited, иначе fallback-проход ниже
	// покажет его как «недостижимые корни» и свёрнутость перестанет работать.
	const hideSubtree = (collection: Collection): void => {
		for (const child of collectionChildren(collections, collection.id, type)) {
			if (visited.has(child.id)) {
				continue;
			}
			visited.add(child.id);
			hideSubtree(child);
		}
	};

	const walk = (collection: Collection, depth: number): void => {
		if (visited.has(collection.id)) {
			return;
		}
		visited.add(collection.id);
		nodes.push({ collection, depth });
		if (collapsed.has(collection.id)) {
			hideSubtree(collection);
			return;
		}
		for (const child of collectionChildren(collections, collection.id, type)) {
			walk(child, depth + 1);
		}
	};

	for (const root of collectionRoots(collections, type)) {
		walk(root, 0);
	}
	for (const collection of collections) {
		if (
			(type === undefined || collection.type === type) &&
			!visited.has(collection.id)
		) {
			walk(collection, 0);
		}
	}
	return nodes;
}

// Цели для переноса элемента/коллекции: тот же тип и не исключённые
// (себя и потомков исключает вызывающий).
export function collectionMoveTargets(
	collections: readonly Collection[],
	type: string,
	excludeIds: ReadonlySet<number>,
): Collection[] {
	return collections.filter(
		(collection) => collection.type === type && !excludeIds.has(collection.id),
	);
}

// Чистое переключение выбора: Set не мутируем, чтобы React увидел новую
// ссылку и не терял выбор между рендерами.
export function toggleSelection(
	selected: ReadonlySet<number>,
	mediaId: number,
): Set<number> {
	const next = new Set(selected);
	if (next.has(mediaId)) {
		next.delete(mediaId);
	} else {
		next.add(mediaId);
	}
	return next;
}

// После удаления/переноса в выборе могли остаться несуществующие id.
// Возвращаем только те, что ещё есть в списке, чтобы счётчик не врал.
export function pruneSelection(
	selected: ReadonlySet<number>,
	availableIds: ReadonlySet<number>,
): Set<number> {
	const next = new Set<number>();
	for (const id of selected) {
		if (availableIds.has(id)) {
			next.add(id);
		}
	}
	return next;
}

import type { Collection } from "../../api/collections";
import type { MediaType } from "../../core/media";

export const BACK_LABEL_KEY = "collections.back";

export const TYPE_PATH: Record<MediaType, "/video" | "/audio" | "/memes"> = {
	video: "/video",
	audio: "/audio",
	image: "/memes",
};

// Id себя и всех потомков: переезд коллекции под них замкнул бы цикл
// (сервер тоже проверяет, но молчание кнопки понятнее ошибки).
export function descendantIds(all: Collection[], rootId: number): Set<number> {
	const excluded = new Set<number>([rootId]);
	const childrenByParent = new Map<number, number[]>();
	for (const collection of all) {
		if (collection.parent_id !== null && collection.parent_id !== undefined) {
			const list = childrenByParent.get(collection.parent_id) ?? [];
			list.push(collection.id);
			childrenByParent.set(collection.parent_id, list);
		}
	}
	const stack = [rootId];
	while (stack.length > 0) {
		const current = stack.pop();
		if (current === undefined) {
			continue;
		}
		for (const child of childrenByParent.get(current) ?? []) {
			if (!excluded.has(child)) {
				excluded.add(child);
				stack.push(child);
			}
		}
	}
	return excluded;
}

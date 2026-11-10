import type { Collection } from "@flux/shared";
import { describe, expect, it } from "vitest";
import {
	asMediaType,
	collectionBreadcrumbs,
	collectionChildren,
	collectionDescendantIds,
	collectionMoveTargets,
	flattenCollectionTree,
	pruneSelection,
	toggleSelection,
} from "./tree";

function collection(
	id: number,
	type = "video",
	parentId: number | null = null,
): Collection {
	return {
		id,
		user_id: 1,
		name: `Collection ${id}`,
		type,
		parent_id: parentId,
		created_at: "",
		updated_at: "",
	};
}

describe("collectionChildren", () => {
	const all = [
		collection(1),
		collection(2, "video", 1),
		collection(3, "video", 1),
		collection(4, "audio", 1),
	];

	it("возвращает прямых детей в порядке списка", () => {
		expect(collectionChildren(all, 1).map((item) => item.id)).toEqual([
			2, 3, 4,
		]);
	});

	it("фильтрует по типу, если он задан", () => {
		expect(collectionChildren(all, 1, "audio").map((item) => item.id)).toEqual([
			4,
		]);
	});

	it("у коллекции без детей пусто", () => {
		expect(collectionChildren(all, 4)).toEqual([]);
	});
});

describe("collectionDescendantIds", () => {
	it("включает саму коллекцию, детей и внуков", () => {
		const all = [
			collection(1),
			collection(2, "video", 1),
			collection(3, "video", 2),
			collection(4, "video", 3),
		];
		expect([...collectionDescendantIds(all, 1)].sort()).toEqual([1, 2, 3, 4]);
		expect([...collectionDescendantIds(all, 2)].sort()).toEqual([2, 3, 4]);
	});

	it("не зависает на цикле в данных", () => {
		const all = [collection(1, "video", 2), collection(2, "video", 1)];
		expect([...collectionDescendantIds(all, 1)].sort()).toEqual([1, 2]);
	});

	it("игнорирует чужие поддеревья", () => {
		const all = [collection(1), collection(2, "video", 1), collection(9)];
		expect([...collectionDescendantIds(all, 1)].sort()).toEqual([1, 2]);
	});
});

describe("collectionBreadcrumbs", () => {
	it("строит путь от корня до текущей", () => {
		const all = [
			collection(1),
			collection(2, "video", 1),
			collection(3, "video", 2),
		];
		expect(collectionBreadcrumbs(all, 3).map((item) => item.id)).toEqual([
			1, 2, 3,
		]);
	});

	it("для корня путь из одного элемента", () => {
		expect(
			collectionBreadcrumbs([collection(1)], 1).map((item) => item.id),
		).toEqual([1]);
	});

	it("обрезает битую цепочку и цикл", () => {
		const all = [
			collection(2, "video", 404),
			collection(3, "video", 4),
			collection(4, "video", 3),
		];
		expect(collectionBreadcrumbs(all, 2).map((item) => item.id)).toEqual([2]);
		expect(collectionBreadcrumbs(all, 3).map((item) => item.id)).toEqual([
			4, 3,
		]);
	});
});

describe("flattenCollectionTree", () => {
	const all = [
		collection(1),
		collection(2, "video", 1),
		collection(3, "video", 2),
		collection(4, "audio"),
		collection(5, "video", 999),
	];

	it("выдаёт корни и вложенные с глубиной", () => {
		expect(
			flattenCollectionTree(all, "video", new Set()).map((node) => [
				node.collection.id,
				node.depth,
			]),
		).toEqual([
			[1, 0],
			[2, 1],
			[3, 2],
			[5, 0],
		]);
	});

	it("свёрнутый узел скрывает поддерево", () => {
		expect(
			flattenCollectionTree(all, "video", new Set([1])).map(
				(node) => node.collection.id,
			),
		).toEqual([1, 5]);
	});

	it("без типа показывает все коллекции", () => {
		expect(
			flattenCollectionTree(all, undefined, new Set()).map(
				(node) => node.collection.id,
			),
		).toEqual([1, 2, 3, 4, 5]);
	});

	it("показывает недостижимый цикл как корень", () => {
		const cycle = [collection(7, "video", 8), collection(8, "video", 7)];
		expect(
			flattenCollectionTree(cycle, "video", new Set()).map(
				(node) => node.collection.id,
			),
		).toEqual([7, 8]);
	});
});

describe("collectionMoveTargets", () => {
	it("оставляет тот же тип и исключает запрещённые id", () => {
		const all = [collection(1), collection(2, "audio"), collection(3)];
		expect(
			collectionMoveTargets(all, "video", new Set([3])).map((item) => item.id),
		).toEqual([1]);
	});
});

describe("selection", () => {
	it("переключает id, не мутируя исходный Set", () => {
		const initial = new Set([1]);
		const added = toggleSelection(initial, 2);
		expect([...added].sort()).toEqual([1, 2]);
		expect([...initial]).toEqual([1]);
		expect([...toggleSelection(added, 1)].sort()).toEqual([2]);
	});

	it("pruneSelection убирает исчезнувшие id", () => {
		expect([...pruneSelection(new Set([1, 2, 3]), new Set([2, 3, 4]))]).toEqual(
			[2, 3],
		);
	});
});

describe("asMediaType", () => {
	it("принимает известные типы и отсекает мусор", () => {
		expect(asMediaType("video")).toBe("video");
		expect(asMediaType("audio")).toBe("audio");
		expect(asMediaType("image")).toBe("image");
		expect(asMediaType("unknown")).toBeNull();
	});
});

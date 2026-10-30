import { describe, expect, it } from "vitest";
import type { Media } from "../../core/media";
import {
	type AudioQueueState,
	emptyQueue,
	pickNextIndex,
	pickPreviousIndex,
	removeTrack,
	selectIndex,
	shiftPlayedIndices,
	startQueue,
} from "./audioQueue";

function media(id: number): Media {
	return {
		id,
		title: `Трек ${id}`,
		filename: `${id}.mp3`,
		year: 2024,
		description: "",
		type: "audio",
		artists: [],
		album: "",
		genre: "",
		duration: 180,
		width: 0,
		height: 0,
		file_size: 1,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
	};
}

function queue(ids: number[], index: number): AudioQueueState {
	return { items: ids.map(media), index };
}

function ids(state: AudioQueueState): number[] {
	return state.items.map((item) => item.id);
}

describe("audioQueue", () => {
	it("startQueue зажимает стартовый индекс в границы списка", () => {
		const items = [media(1), media(2)];
		expect(startQueue(items, 5).index).toBe(1);
		expect(startQueue(items, -2).index).toBe(0);
		expect(startQueue([], 0)).toBe(emptyQueue);
	});

	it("selectIndex игнорирует выход за границы", () => {
		const state = queue([1, 2], 0);
		expect(selectIndex(state, 1).index).toBe(1);
		expect(selectIndex(state, 2)).toBe(state);
		expect(selectIndex(state, -1)).toBe(state);
	});

	it("удаление трека выше текущего сдвигает индекс", () => {
		const state = removeTrack(queue([1, 2, 3], 1), 0);
		expect(ids(state)).toEqual([2, 3]);
		expect(state.index).toBe(0);
	});

	it("удаление текущего трека оставляет на его месте следующий", () => {
		const state = removeTrack(queue([1, 2, 3], 1), 1);
		expect(ids(state)).toEqual([1, 3]);
		expect(state.index).toBe(1);
	});

	it("удаление последнего текущего трека откатывается на предыдущий", () => {
		const state = removeTrack(queue([1, 2, 3], 2), 2);
		expect(ids(state)).toEqual([1, 2]);
		expect(state.index).toBe(1);
	});

	it("удаление трека ниже текущего не двигает индекс", () => {
		const state = removeTrack(queue([1, 2, 3], 0), 2);
		expect(ids(state)).toEqual([1, 2]);
		expect(state.index).toBe(0);
	});

	it("удаление последнего трека отдаёт пустую очередь", () => {
		expect(removeTrack(queue([1], 0), 0)).toBe(emptyQueue);
	});

	it("pickNextIndex идёт по порядку и останавливается в конце", () => {
		expect(
			pickNextIndex(queue([1, 2, 3], 0), { shuffle: false, repeat: "off" }),
		).toBe(1);
		expect(
			pickNextIndex(queue([1, 2, 3], 2), { shuffle: false, repeat: "off" }),
		).toBeNull();
	});

	it("pickNextIndex зацикливает очередь при повторе", () => {
		expect(
			pickNextIndex(queue([1, 2, 3], 2), { shuffle: false, repeat: "all" }),
		).toBe(0);
	});

	it("pickNextIndex выбирает другой трек при перемешивании", () => {
		const next = pickNextIndex(queue([1, 2, 3], 0), {
			shuffle: true,
			repeat: "off",
			random: () => 0.9,
		});
		expect(next).toBe(2);
	});

	it("pickNextIndex не повторяет текущий трек сразу", () => {
		// random указывает на текущий индекс: он исключён из пула.
		const next = pickNextIndex(queue([1, 2, 3], 1), {
			shuffle: true,
			repeat: "off",
			random: () => 0.4,
		});
		expect(next).toBe(0);
	});

	it("pickNextIndex пропускает уже сыгранные треки", () => {
		const next = pickNextIndex(queue([1, 2, 3], 0), {
			shuffle: true,
			repeat: "off",
			played: new Set([0, 1]),
			random: () => 0.1,
		});
		expect(next).toBe(2);
	});

	it("pickNextIndex останавливается, когда перемешанное сыграно", () => {
		expect(
			pickNextIndex(queue([1, 2], 1), {
				shuffle: true,
				repeat: "off",
				played: new Set([0, 1]),
			}),
		).toBeNull();
	});

	it("pickNextIndex начинает свежий круг при повторе очереди", () => {
		const next = pickNextIndex(queue([1, 2, 3], 2), {
			shuffle: true,
			repeat: "all",
			played: new Set([0, 1, 2]),
			random: () => 0.1,
		});
		expect(next).not.toBe(2);
		expect(next).not.toBeNull();
	});

	it("pickNextIndex в пустой очереди останавливается", () => {
		expect(
			pickNextIndex(emptyQueue, { shuffle: false, repeat: "all" }),
		).toBeNull();
	});

	it("pickPreviousIndex идёт назад и стоит в начале", () => {
		expect(
			pickPreviousIndex(queue([1, 2, 3], 1), {
				shuffle: false,
				repeat: "off",
			}),
		).toBe(0);
		expect(
			pickPreviousIndex(queue([1, 2, 3], 0), {
				shuffle: false,
				repeat: "off",
			}),
		).toBeNull();
	});

	it("pickPreviousIndex зацикливается на последний при повторе", () => {
		expect(
			pickPreviousIndex(queue([1, 2, 3], 0), {
				shuffle: false,
				repeat: "all",
			}),
		).toBe(2);
	});

	it("pickPreviousIndex выбирает случайный другой при перемешивании", () => {
		const previous = pickPreviousIndex(queue([1, 2, 3], 1), {
			shuffle: true,
			repeat: "off",
			random: () => 0.9,
		});
		expect(previous).toBe(2);
	});

	it("shiftPlayedIndices сдвигает индексы после удаления", () => {
		expect(shiftPlayedIndices(new Set([0, 1, 2]), 1)).toEqual(new Set([0, 1]));
		expect(shiftPlayedIndices(new Set([0, 2]), 0)).toEqual(new Set([1]));
	});
});

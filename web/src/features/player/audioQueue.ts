import type { Media } from "../../core/media";

// Чистая машина очереди: провайдер отвечает за элемент и эффекты,
// а перестановки индексов живут здесь и проверяются юнит-тестами.
export interface AudioQueueState {
	items: Media[];
	index: number;
}

export const emptyQueue: AudioQueueState = { items: [], index: 0 };

export function currentMedia(state: AudioQueueState): Media | null {
	return state.items[state.index] ?? null;
}

export function startQueue(
	items: Media[],
	startIndex: number,
): AudioQueueState {
	if (items.length === 0) {
		return emptyQueue;
	}
	const index = Math.min(Math.max(startIndex, 0), items.length - 1);
	return { items, index };
}

export function selectIndex(
	state: AudioQueueState,
	index: number,
): AudioQueueState {
	if (index < 0 || index >= state.items.length) {
		return state;
	}
	return { ...state, index };
}

export function removeTrack(
	state: AudioQueueState,
	index: number,
): AudioQueueState {
	if (index < 0 || index >= state.items.length) {
		return state;
	}
	const items = state.items.filter((_, position) => position !== index);
	if (items.length === 0) {
		return emptyQueue;
	}
	if (index < state.index) {
		return { items, index: state.index - 1 };
	}
	if (index === state.index) {
		// Текущий трек удалён: на его место встаёт следующий, а если его
		// нет — предыдущий.
		return { items, index: Math.min(state.index, items.length - 1) };
	}
	return { items, index: state.index };
}

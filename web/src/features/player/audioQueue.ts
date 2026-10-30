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

export type RepeatMode = "off" | "all" | "one";

// Куда идти по next (кнопка и конец трека): индекс или null — стоп.
// Повтор одного обрабатывается перезапуском, а не переходом, поэтому
// здесь "one" останавливает очередь как "off": вызывающий смотрит
// на repeat отдельно.
//
// При shuffle уже сыгранные треки (played) пропускаются, а текущий
// никогда не выбирается сразу повторно: иначе при repeat "off" очередь
// играла бы бесконечно по кругу вместо остановки в конце.
export function pickNextIndex(
	state: AudioQueueState,
	options: {
		shuffle: boolean;
		repeat: RepeatMode;
		played?: ReadonlySet<number>;
		random?: () => number;
	},
): number | null {
	const { shuffle, repeat } = options;
	const last = state.items.length - 1;
	if (last < 0) {
		return null;
	}
	if (shuffle && state.items.length > 1) {
		const random = options.random ?? Math.random;
		const pool: number[] = [];
		for (let index = 0; index < state.items.length; index += 1) {
			if (index !== state.index && !(options.played?.has(index) ?? false)) {
				pool.push(index);
			}
		}
		if (pool.length === 0) {
			// Всё сыграно: без повтора — стоп, с повтором — свежий круг
			// (вызывающий при этом сбрасывает played).
			if (repeat !== "all") {
				return null;
			}
			for (let index = 0; index < state.items.length; index += 1) {
				if (index !== state.index) {
					pool.push(index);
				}
			}
		}
		return pool[Math.floor(random() * pool.length) % pool.length];
	}
	if (state.index < last) {
		return state.index + 1;
	}
	return repeat === "all" ? 0 : null;
}

// Куда идти по «Предыдущий»: индекс или null — стоим на месте.
// Симметрично next: при repeat "all" с первого трека уходим на последний,
// при shuffle — на случайный другой.
export function pickPreviousIndex(
	state: AudioQueueState,
	options: {
		shuffle: boolean;
		repeat: RepeatMode;
		random?: () => number;
	},
): number | null {
	if (state.items.length === 0) {
		return null;
	}
	if (options.shuffle && state.items.length > 1) {
		const random = options.random ?? Math.random;
		const pool: number[] = [];
		for (let index = 0; index < state.items.length; index += 1) {
			if (index !== state.index) {
				pool.push(index);
			}
		}
		return pool[Math.floor(random() * pool.length) % pool.length];
	}
	if (state.index > 0) {
		return state.index - 1;
	}
	if (options.repeat === "all" && state.items.length > 1) {
		return state.items.length - 1;
	}
	return null;
}

// После удаления трека индексы сыгранных сдвигаются: удалённый выпадает,
// стоящие выше съезжают на один. Без этого shuffle пропускал бы не те треки.
export function shiftPlayedIndices(
	played: ReadonlySet<number>,
	removed: number,
): Set<number> {
	const next = new Set<number>();
	for (const index of played) {
		if (index === removed) {
			continue;
		}
		next.add(index > removed ? index - 1 : index);
	}
	return next;
}

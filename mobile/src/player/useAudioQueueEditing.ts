import {
	type AudioQueueState,
	emptyQueue,
	movePlayedIndices,
	moveTrack,
	removeTrack,
	shiftPlayedIndices,
} from "@flux/shared";
import {
	type Dispatch,
	type RefObject,
	type SetStateAction,
	useCallback,
} from "react";

interface UseAudioQueueEditingOptions {
	queueState: AudioQueueState;
	setQueueState: Dispatch<SetStateAction<AudioQueueState>>;
	setPlayed: Dispatch<SetStateAction<ReadonlySet<number>>>;
	desiredPlayingRef: RefObject<boolean>;
	changeTrack: (next: AudioQueueState, play: boolean) => void;
	unloadSource: () => void;
}

export interface AudioQueueEditing {
	move: (from: number, to: number) => void;
	removeAt: (index: number) => void;
	clear: () => void;
}

// Перестановка/удаление/очистка очереди. Вынесено из транспорта, чтобы
// у каждого хука была одна зона ответственности и лимит размера.
export function useAudioQueueEditing({
	queueState,
	setQueueState,
	setPlayed,
	desiredPlayingRef,
	changeTrack,
	unloadSource,
}: UseAudioQueueEditingOptions): AudioQueueEditing {
	const clear = useCallback(() => {
		desiredPlayingRef.current = false;
		unloadSource();
		setQueueState(emptyQueue);
		setPlayed(new Set());
	}, [desiredPlayingRef, setPlayed, setQueueState, unloadSource]);

	const move = useCallback(
		(from: number, to: number) => {
			const length = queueState.items.length;
			if (from < 0 || from >= length || to < 0 || to >= length || from === to) {
				return;
			}
			// Functional updater: два быстрых move подряд не должны
			// перезаписывать очередь устаревшим снимком.
			setQueueState((prev) => moveTrack(prev, from, to));
			setPlayed((prev) => movePlayedIndices(prev, from, to));
		},
		[queueState.items.length, setPlayed, setQueueState],
	);

	const removeAt = useCallback(
		(removeIndex: number) => {
			if (removeIndex < 0 || removeIndex >= queueState.items.length) {
				return;
			}
			if (queueState.items.length === 1) {
				clear();
				return;
			}
			setPlayed((prev) => shiftPlayedIndices(prev, removeIndex));
			const nextState = removeTrack(queueState, removeIndex);
			if (removeIndex === queueState.index) {
				// Текущий трек удалён: на его место встаёт следующий.
				changeTrack(nextState, desiredPlayingRef.current);
				return;
			}
			setQueueState(nextState);
		},
		[
			changeTrack,
			clear,
			desiredPlayingRef,
			queueState,
			setPlayed,
			setQueueState,
		],
	);

	return { move, removeAt, clear };
}

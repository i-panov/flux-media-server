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
	useEffect,
	useRef,
} from "react";

interface UseAudioQueueEditingOptions {
	queueState: AudioQueueState;
	setQueueState: Dispatch<SetStateAction<AudioQueueState>>;
	setPlayed: Dispatch<SetStateAction<ReadonlySet<number>>>;
	desiredPlayingRef: RefObject<boolean>;
	changeTrack: (next: AudioQueueState, play: boolean) => void;
	unloadSource: () => void;
	/** Пользователь уже менял очередь: гидратация не должна её перетереть. */
	markUserAction: () => void;
	/** Сбросить userStarted при очистке очереди. */
	resetUserStarted: () => void;
	setDesiredPlaying: (value: boolean) => void;
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
	markUserAction,
	resetUserStarted,
	setDesiredPlaying,
}: UseAudioQueueEditingOptions): AudioQueueEditing {
	// Свежая очередь для составных действий: setQueueState функциональный,
	// но changeTrack нужен готовый nextState. Ref обновляется и в updater,
	// поэтому два быстрых remove не перезаписывают очередь старым снимком.
	const queueRef = useRef(queueState);
	useEffect(() => {
		queueRef.current = queueState;
	}, [queueState]);

	const clear = useCallback(() => {
		markUserAction();
		resetUserStarted();
		setDesiredPlaying(false);
		unloadSource();
		queueRef.current = emptyQueue;
		setQueueState(emptyQueue);
		setPlayed(new Set());
	}, [
		markUserAction,
		resetUserStarted,
		setDesiredPlaying,
		setPlayed,
		setQueueState,
		unloadSource,
	]);

	const move = useCallback(
		(from: number, to: number) => {
			const length = queueRef.current.items.length;
			if (from < 0 || from >= length || to < 0 || to >= length || from === to) {
				return;
			}
			markUserAction();
			// Functional updater: два быстрых move подряд не должны
			// перезаписывать очередь устаревшим снимком.
			setQueueState((prev) => {
				const next = moveTrack(prev, from, to);
				queueRef.current = next;
				return next;
			});
			setPlayed((prev) => movePlayedIndices(prev, from, to));
		},
		[markUserAction, setPlayed, setQueueState],
	);

	const removeAt = useCallback(
		(removeIndex: number) => {
			const current = queueRef.current;
			if (removeIndex < 0 || removeIndex >= current.items.length) {
				return;
			}
			markUserAction();
			if (current.items.length === 1) {
				clear();
				return;
			}
			const nextState = removeTrack(current, removeIndex);
			queueRef.current = nextState;
			setQueueState((prev) => {
				const next = removeTrack(prev, removeIndex);
				queueRef.current = next;
				return next;
			});
			setPlayed((prev) => shiftPlayedIndices(prev, removeIndex));
			if (removeIndex === current.index) {
				// Текущий трек удалён: на его место встаёт следующий.
				changeTrack(nextState, desiredPlayingRef.current);
			}
		},
		[
			changeTrack,
			clear,
			desiredPlayingRef,
			markUserAction,
			setPlayed,
			setQueueState,
		],
	);

	return { move, removeAt, clear };
}

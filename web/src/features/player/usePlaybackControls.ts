import { type RefObject, useCallback, useState } from "react";
import type { Media } from "../../core/media";
import type { useMediaProgress } from "../media/useMediaProgress";
import { playAudio } from "./audioPlayback";
import {
	type AudioQueueState,
	currentMedia,
	emptyQueue,
	enqueueItems,
	movePlayedIndices,
	moveTrack,
	pickNextIndex,
	pickPreviousIndex,
	type RepeatMode,
	removeTrack,
	selectIndex,
	shiftPlayedIndices,
	startQueue,
} from "./audioQueue";
import { clearPersistedQueue } from "./playerPersistence";

type Progress = Pick<ReturnType<typeof useMediaProgress>, "handlePause">;

function useQueueMove(
	setQueueState: React.Dispatch<React.SetStateAction<AudioQueueState>>,
	setPlayed: React.Dispatch<React.SetStateAction<ReadonlySet<number>>>,
) {
	return useCallback(
		(from: number, to: number) => {
			setQueueState((prev) => moveTrack(prev, from, to));
			setPlayed((prev) => movePlayedIndices(prev, from, to));
		},
		[setQueueState, setPlayed],
	);
}

// Кнопки транспорта: очередь, воспроизведение, громкость и режимы.
// Провайдер отвечает за элемент и эффекты, а вся механика — здесь,
// чтобы компонент оставался в лимите размера.
export function usePlaybackControls({
	queueState,
	setQueueState,
	current,
	currentId,
	audioRef,
	shouldPlayRef,
	shuffle,
	repeat,
	progress,
	markTime,
	setError,
	setPlaying,
	setVolumeState,
	onPlayError,
	initialPlayed,
}: {
	queueState: AudioQueueState;
	setQueueState: React.Dispatch<React.SetStateAction<AudioQueueState>>;
	current: Media | null;
	currentId: number;
	audioRef: RefObject<HTMLAudioElement | null>;
	shouldPlayRef: RefObject<boolean>;
	shuffle: boolean;
	repeat: RepeatMode;
	progress: Progress;
	markTime: (seconds: number) => void;
	setError: (message: string | null) => void;
	setPlaying: (playing: boolean) => void;
	setVolumeState: (volume: number) => void;
	onPlayError: (message: string) => void;
	initialPlayed?: ReadonlySet<number>;
}) {
	const queue = queueState.items;
	// Сыграно в перемешанном режиме, иначе при repeat "off" очередь
	// играла бы по кругу. Начальное — из хранилища.
	const [played, setPlayed] = useState<ReadonlySet<number>>(
		() => initialPlayed ?? new Set([queueState.index]),
	);

	const playQueue = useCallback(
		(items: Media[], startIndex = 0) => {
			if (items.length === 0) {
				return;
			}
			const nextState = startQueue(items, startIndex);
			shouldPlayRef.current = true;
			setError(null);
			setQueueState(nextState);
			setPlayed(new Set([nextState.index]));
			const element = audioRef.current;
			if (element !== null && currentMedia(nextState)?.id === currentId) {
				playAudio(element, onPlayError);
			}
		},
		[audioRef, currentId, onPlayError, setError, setQueueState, shouldPlayRef],
	);

	const playMedia = useCallback(
		(media: Media) => playQueue([media], 0),
		[playQueue],
	);

	const enqueue = useCallback(
		(media: Media) => {
			setQueueState((prev) => enqueueItems(prev, [media]));
		},
		[setQueueState],
	);

	const toggle = useCallback(() => {
		const element = audioRef.current;
		if (element === null || current === null) {
			return;
		}
		if (element.paused) {
			shouldPlayRef.current = true;
			// Повтор после сбоя: старая ошибка не должна висеть, если
			// воспроизведение на этот раз пошло.
			setError(null);
			playAudio(element, onPlayError);
		} else {
			progress.handlePause();
			shouldPlayRef.current = false;
			element.pause();
		}
	}, [audioRef, current, onPlayError, progress, setError, shouldPlayRef]);

	const select = useCallback(
		(nextIndex: number) => {
			if (nextIndex < 0 || nextIndex >= queue.length) {
				return;
			}
			shouldPlayRef.current = true;
			setError(null);
			setPlayed((prev) => new Set(prev).add(nextIndex));
			setQueueState((prev) => selectIndex(prev, nextIndex));
		},
		[queue.length, setError, setQueueState, shouldPlayRef],
	);

	const next = useCallback(() => {
		const target = pickNextIndex(queueState, {
			shuffle,
			repeat,
			played,
		});
		if (target === null) {
			shouldPlayRef.current = false;
			progress.handlePause();
			audioRef.current?.pause();
			return;
		}
		if (played.size >= queueState.items.length) {
			// Свежий круг при repeat "all": история началась заново.
			setPlayed(new Set([target]));
		} else {
			setPlayed((prev) => new Set(prev).add(target));
		}
		select(target);
	}, [
		audioRef,
		played,
		progress,
		queueState,
		repeat,
		select,
		shouldPlayRef,
		shuffle,
	]);

	const previous = useCallback(() => {
		const element = audioRef.current;
		if (element !== null && element.currentTime > 3) {
			element.currentTime = 0;
			markTime(0);
			return;
		}
		const target = pickPreviousIndex(queueState, { shuffle, repeat });
		if (target === null) {
			return;
		}
		select(target);
	}, [audioRef, markTime, queueState, repeat, select, shuffle]);

	const seek = useCallback(
		(seconds: number) => {
			const element = audioRef.current;
			if (element === null) {
				return;
			}
			element.currentTime = seconds;
			markTime(seconds);
		},
		[audioRef, markTime],
	);

	const setVolume = useCallback(
		(value: number) => {
			const normalized = Math.min(Math.max(value, 0), 1);
			setVolumeState(normalized);
			if (audioRef.current !== null) {
				audioRef.current.volume = normalized;
			}
		},
		[audioRef, setVolumeState],
	);

	const clear = useCallback(() => {
		shouldPlayRef.current = false;
		const element = audioRef.current;
		if (element !== null) {
			element.pause();
			element.removeAttribute("src");
			element.load();
		}
		setQueueState(emptyQueue);
		setPlaying(false);
		setError(null);
		setPlayed(new Set());
		clearPersistedQueue();
	}, [audioRef, setError, setPlaying, setQueueState, shouldPlayRef]);

	const move = useQueueMove(setQueueState, setPlayed);
	const removeAt = useCallback(
		(removeIndex: number) => {
			if (removeIndex < 0 || removeIndex >= queue.length) {
				return;
			}
			if (queue.length === 1) {
				clear();
				return;
			}
			// Удаление сохраняет состояние паузы: играло — продолжает
			// следующим, стояло — следующий тоже молчит.
			// Индексы сыгранных съезжают вместе с очередью, иначе shuffle
			// пропускал бы не те треки.
			setPlayed((prev) => shiftPlayedIndices(prev, removeIndex));
			setQueueState((prev) => removeTrack(prev, removeIndex));
		},
		[clear, queue.length, setQueueState],
	);

	return {
		played,
		playQueue,
		playMedia,
		enqueue,
		toggle,
		next,
		previous,
		select,
		seek,
		setVolume,
		move,
		removeAt,
		clear,
	};
}

import {
	type AudioQueueState,
	currentMedia,
	enqueueItems,
	type Media,
	pickNextIndex,
	pickPreviousIndex,
	type RepeatMode,
	selectIndex,
	startQueue,
} from "@flux/shared";
import type { AudioPlayer, AudioStatus } from "expo-audio";
import {
	type Dispatch,
	type RefObject,
	type SetStateAction,
	useCallback,
} from "react";
import {
	shouldPauseOnToggle,
	shouldResumeAfterTrackChange,
	wasPlayingBeforeChange,
} from "./audioPlaybackPolicy";
import type { AudioSourceOptions } from "./useAudioSource";

interface UseAudioQueueControlsOptions {
	queueState: AudioQueueState;
	setQueueState: Dispatch<SetStateAction<AudioQueueState>>;
	played: ReadonlySet<number>;
	setPlayed: Dispatch<SetStateAction<ReadonlySet<number>>>;
	shuffle: boolean;
	repeat: RepeatMode;
	setShuffle: Dispatch<SetStateAction<boolean>>;
	setRepeat: Dispatch<SetStateAction<RepeatMode>>;
	player: AudioPlayer;
	status: AudioStatus;
	desiredPlayingRef: RefObject<boolean>;
	sourceFailed: boolean;
	sourceLoading: boolean;
	isSourceLoaded: (mediaId: number) => boolean;
	loadSource: (media: Media, options: AudioSourceOptions) => void;
	changeTrack: (next: AudioQueueState, play: boolean) => void;
}

// Адаптер к чистой политике: нативный плеер отдаёт playing/isBuffering.
function wasPlayingOnChange(
	player: AudioPlayer,
	desiredPlayingRef: RefObject<boolean>,
	sourceLoading: boolean,
): boolean {
	return wasPlayingBeforeChange({
		playing: player.playing,
		buffering: player.isBuffering,
		loading: sourceLoading,
		desiredPlaying: desiredPlayingRef.current,
	});
}

export interface AudioControls {
	playQueue: (items: Media[], startIndex?: number) => void;
	playMedia: (media: Media) => void;
	enqueue: (media: Media) => void;
	toggle: () => void;
	next: () => void;
	previous: () => void;
	select: (index: number) => void;
	toggleShuffle: () => void;
	cycleRepeat: () => void;
	/** Конец трека: repeat "one" перезапускает, иначе — следующий. */
	finish: () => void;
}

// Механика транспорта: очередь, переключение и режимы. Провайдер отвечает
// за элемент, источник и персист; редактирование очереди — в
// useAudioQueueEditing, чтобы каждый хук оставался в лимите размера.
export function useAudioQueueControls({
	queueState,
	setQueueState,
	played,
	setPlayed,
	shuffle,
	repeat,
	setShuffle,
	setRepeat,
	player,
	status,
	desiredPlayingRef,
	sourceFailed,
	sourceLoading,
	isSourceLoaded,
	loadSource,
	changeTrack,
}: UseAudioQueueControlsOptions): AudioControls {
	const current = currentMedia(queueState);

	const playQueue = useCallback(
		(items: Media[], startIndex = 0) => {
			if (items.length === 0) {
				return;
			}
			const next = startQueue(items, startIndex);
			setPlayed(new Set([next.index]));
			changeTrack(next, true);
		},
		[changeTrack, setPlayed],
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
		if (current === null) {
			return;
		}
		if (
			shouldPauseOnToggle({
				playing: player.playing,
				loading: sourceLoading,
				buffering: player.isBuffering,
				desiredPlaying: desiredPlayingRef.current,
			})
		) {
			desiredPlayingRef.current = false;
			player.pause();
			return;
		}
		desiredPlayingRef.current = true;
		if (sourceFailed || !isSourceLoaded(current.id) || !player.isLoaded) {
			loadSource(current, { play: () => desiredPlayingRef.current });
			return;
		}
		const nearEnd =
			status.didJustFinish ||
			(status.duration > 0 && status.currentTime >= status.duration - 0.5);
		if (!nearEnd) {
			player.play();
			return;
		}
		void (async () => {
			await player.seekTo(0).catch(() => {
				// Источник мог выгрузиться — play ниже всё равно попробует.
			});
			player.play();
		})();
	}, [
		current,
		desiredPlayingRef,
		isSourceLoaded,
		loadSource,
		player,
		sourceFailed,
		sourceLoading,
		status.currentTime,
		status.didJustFinish,
		status.duration,
	]);

	const advance = useCallback(
		(play: boolean) => {
			const target = pickNextIndex(queueState, {
				shuffle,
				repeat,
				played,
			});
			if (target === null) {
				desiredPlayingRef.current = false;
				player.pause();
				return;
			}
			// Свежий круг repeat "all": история shuffle начинается заново.
			const nextPlayed =
				played.size >= queueState.items.length
					? new Set([target])
					: new Set(played).add(target);
			setPlayed(nextPlayed);
			changeTrack(selectIndex(queueState, target), play);
		},
		[
			changeTrack,
			desiredPlayingRef,
			played,
			player,
			queueState,
			repeat,
			setPlayed,
			shuffle,
		],
	);

	const next = useCallback(() => {
		advance(wasPlayingOnChange(player, desiredPlayingRef, sourceLoading));
	}, [advance, desiredPlayingRef, player, sourceLoading]);

	const previous = useCallback(() => {
		if (status.currentTime > 3) {
			void player.seekTo(0).catch(() => {
				// Нет загруженного источника — остаёмся на месте.
			});
			return;
		}
		const target = pickPreviousIndex(queueState, { shuffle, repeat });
		if (target === null) {
			return;
		}
		setPlayed((prev) => new Set(prev).add(target));
		changeTrack(
			selectIndex(queueState, target),
			wasPlayingOnChange(player, desiredPlayingRef, sourceLoading),
		);
	}, [
		changeTrack,
		desiredPlayingRef,
		player,
		queueState,
		repeat,
		setPlayed,
		shuffle,
		sourceLoading,
		status.currentTime,
	]);

	const select = useCallback(
		(index: number) => {
			const nextState = selectIndex(queueState, index);
			if (nextState === queueState) {
				return;
			}
			setPlayed((prev) => new Set(prev).add(index));
			changeTrack(nextState, true);
		},
		[changeTrack, queueState, setPlayed],
	);

	const toggleShuffle = useCallback(() => {
		setShuffle((prev) => !prev);
	}, [setShuffle]);

	const cycleRepeat = useCallback(() => {
		setRepeat((prev) =>
			prev === "off" ? "all" : prev === "all" ? "one" : "off",
		);
	}, [setRepeat]);

	const finish = useCallback(() => {
		// К концу трека status уже playing=false, но звук должен продолжиться:
		// repeat one — с начала, иначе — следующим треком.
		const resume = shouldResumeAfterTrackChange(player.playing, true);
		if (repeat === "one") {
			desiredPlayingRef.current = resume;
			void (async () => {
				await player.seekTo(0).catch(() => {
					// Повтор с нуля не удался — остаёмся на паузе.
				});
				if (resume) {
					player.play();
				}
			})();
			return;
		}
		advance(resume);
	}, [advance, desiredPlayingRef, player, repeat]);

	return {
		playQueue,
		playMedia,
		enqueue,
		toggle,
		next,
		previous,
		select,
		toggleShuffle,
		cycleRepeat,
		finish,
	};
}

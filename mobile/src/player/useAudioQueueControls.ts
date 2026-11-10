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
	/** Ручной seek/±10: отменяет поздний server-resume. */
	markUserStarted: () => void;
	/** Ручной retry после 401 снова разрешает server resume. */
	resetResumeGuards: () => void;
	/** Пользователь уже менял очередь/режимы: гидратация не должна их перетереть. */
	markUserAction: () => void;
	/** Синхронно обновить ref и state-намерение (pending-иконка). */
	setDesiredPlaying: (value: boolean) => void;
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

// Конец трека или позиция у самого конца: toggle должен перезапустить трек,
// а не вызвать play() на уже завершившемся источнике.
function isNearEnd(status: AudioStatus): boolean {
	return (
		status.didJustFinish ||
		(status.duration > 0 && status.currentTime >= status.duration - 0.5)
	);
}

export interface AudioControls {
	playQueue: (items: Media[], startIndex?: number) => void;
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
	markUserAction,
	markUserStarted,
	resetResumeGuards,
	setDesiredPlaying,
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

	const enqueue = useCallback(
		(media: Media) => {
			markUserAction();
			setQueueState((prev) => enqueueItems(prev, [media]));
		},
		[markUserAction, setQueueState],
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
			setDesiredPlaying(false);
			player.pause();
			return;
		}
		setDesiredPlaying(true);
		// Загрузка уже идёт: apply прочитает актуальное намерение при
		// завершении. Повторный loadSource только сбросил бы прогресс.
		if (sourceLoading) {
			return;
		}
		if (sourceFailed || !isSourceLoaded(current.id) || !player.isLoaded) {
			// Ручной retry после неудачного 401-recover: новая generation
			// получает право на fetchProgress/resume.
			resetResumeGuards();
			loadSource(current, { play: () => desiredPlayingRef.current });
			return;
		}
		if (!isNearEnd(status)) {
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
		resetResumeGuards,
		setDesiredPlaying,
		sourceFailed,
		sourceLoading,
		status,
	]);

	const advance = useCallback(
		(play: boolean) => {
			const target = pickNextIndex(queueState, {
				shuffle,
				repeat,
				played,
			});
			if (target === null) {
				setDesiredPlaying(false);
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
			played,
			player,
			queueState,
			repeat,
			setDesiredPlaying,
			setPlayed,
			shuffle,
		],
	);
	const next = () => {
		advance(wasPlayingOnChange(player, desiredPlayingRef, sourceLoading));
	};

	const previous = useCallback(() => {
		if (status.currentTime > 3) {
			markUserStarted();
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
		markUserStarted,
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
			// Текущий трек не перезапускаем с 0: selectIndex всегда создаёт
			// новый объект, поэтому сравнение по ссылке здесь не работает.
			if (index === queueState.index) {
				return;
			}
			const nextState = selectIndex(queueState, index);
			setPlayed((prev) => new Set(prev).add(index));
			changeTrack(nextState, true);
		},
		[changeTrack, queueState, setPlayed],
	);

	const toggleShuffle = useCallback(() => {
		markUserAction();
		setShuffle((prev) => !prev);
	}, [markUserAction, setShuffle]);

	const cycleRepeat = useCallback(() => {
		markUserAction();
		setRepeat((prev) =>
			prev === "off" ? "all" : prev === "all" ? "one" : "off",
		);
	}, [markUserAction, setRepeat]);

	const finish = useCallback(() => {
		// К концу трека status уже playing=false, но звук должен продолжиться:
		// repeat one — с начала, иначе — следующим треком.
		const resume = shouldResumeAfterTrackChange(player.playing, true);
		if (repeat === "one") {
			setDesiredPlaying(resume);
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
	}, [advance, player, repeat, setDesiredPlaying]);

	return {
		playQueue,
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

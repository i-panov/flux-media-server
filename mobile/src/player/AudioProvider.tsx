import {
	type AudioQueueState,
	currentMedia,
	type Media,
	type RepeatMode,
} from "@flux/shared";
import { useEventListener, useReleasingSharedObject } from "expo";
import {
	createAudioPlayer,
	setAudioModeAsync,
	useAudioPlayerStatus,
} from "expo-audio";
import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useEffect,
	useMemo,
	useRef,
	useState,
} from "react";
import { useContinueWatching } from "../api/progress";
import { useLocalReset } from "../auth/reset";
import { useDownloadedPathResolver } from "../downloads/DownloadProvider";
import { t, useLanguage } from "../i18n";
import { desiredAfterStatus } from "./audioPlaybackPolicy";
import { shouldPreemptResumeOn401 } from "./audioProgress";
import { useAudioArtistSync } from "./useAudioArtistSync";
import { useAudioProgress } from "./useAudioProgress";
import {
	type AudioControls,
	useAudioQueueControls,
} from "./useAudioQueueControls";
import {
	type AudioQueueEditing,
	useAudioQueueEditing,
} from "./useAudioQueueEditing";
import { useAudioQueueState } from "./useAudioQueueState";
import { useAudioRate } from "./useAudioRate";
import { useAudioSeek } from "./useAudioSeek";
import { useAudioSource } from "./useAudioSource";

// 500 мс — дефолт expo-audio: мини-бару хватает, лишних перерисовок нет.
const STATUS_UPDATE_INTERVAL_MS = 500;

export interface AudioState {
	queue: Media[];
	index: number;
	current: Media | null;
	/** Играет или вот-вот заиграет: иконка не должна отставать на 500 мс. */
	displayPlaying: boolean;
	currentTime: number;
	duration: number;
	shuffle: boolean;
	repeat: RepeatMode;
	error: string | null;
	loading: boolean;
	buffering: boolean;
	rate: number;
}

export interface AudioActions extends AudioControls, AudioQueueEditing {
	seek: (seconds: number) => void;
	cycleRate: () => void;
}

const AudioStateContext = createContext<AudioState | null>(null);
const AudioActionsContext = createContext<AudioActions | null>(null);

export function useAudioState(): AudioState {
	const value = useContext(AudioStateContext);
	if (value === null) {
		throw new Error("useAudioState must be used inside AudioProvider");
	}
	return value;
}

export function useAudioActions(): AudioActions {
	const value = useContext(AudioActionsContext);
	if (value === null) {
		throw new Error("useAudioActions must be used inside AudioProvider");
	}
	return value;
}

// Actions-контекст должен иметь неизменную идентичность: методы читают
// свежие замыкания из ref, а подписчики не ререндерятся от currentTime.
function useStableAudioActions(actions: AudioActions): AudioActions {
	const latest = useRef(actions);
	useEffect(() => {
		latest.current = actions;
	}, [actions]);
	return useMemo<AudioActions>(
		() => ({
			playQueue: (items, startIndex) =>
				latest.current.playQueue(items, startIndex),
			restoreQueue: (items, startIndex) =>
				latest.current.restoreQueue(items, startIndex),
			enqueue: (media) => latest.current.enqueue(media),
			toggle: () => latest.current.toggle(),
			next: () => latest.current.next(),
			previous: () => latest.current.previous(),
			select: (index) => latest.current.select(index),
			toggleShuffle: () => latest.current.toggleShuffle(),
			cycleRepeat: () => latest.current.cycleRepeat(),
			finish: () => latest.current.finish(),
			move: (from, to) => latest.current.move(from, to),
			removeAt: (index) => latest.current.removeAt(index),
			clear: () => latest.current.clear(),
			seek: (seconds) => latest.current.seek(seconds),
			cycleRate: () => latest.current.cycleRate(),
		}),
		[],
	);
}

// eslint-disable-next-line max-lines-per-function -- провайдер держит источник, очередь и восстановление.
export function AudioProvider({ children }: { children: ReactNode }) {
	useLanguage();
	// Императивный createAudioPlayer + useReleasingSharedObject: плеер
	// переживает ререндеры и освобождается ровно один раз при размонтировании.
	const player = useReleasingSharedObject(
		() =>
			createAudioPlayer(null, { updateInterval: STATUS_UPDATE_INTERVAL_MS }),
		[],
	);
	const status = useAudioPlayerStatus(player);
	const desiredPlayingRef = useRef(false);
	const {
		queueState,
		setQueueState,
		played,
		setPlayed,
		shuffle,
		repeat,
		setShuffle,
		setRepeat,
		markUserAction,
		hydrated: queueHydrated,
	} = useAudioQueueState();

	const current = currentMedia(queueState);
	const getDownloadedPath = useDownloadedPathResolver();
	const {
		failed: sourceFailed,
		loading: sourceLoading,
		load: loadSource,
		recover: recoverSource,
		unload: unloadSource,
		isLoaded: isSourceLoaded,
		generation: sourceGeneration,
	} = useAudioSource(player, getDownloadedPath);
	const { rate, cycleRate } = useAudioRate(player);
	const [desiredPlaying, setDesiredPlayingState] = useState(false);
	// Ref нужен синхронно (in-flight load читает его при завершении), state —
	// для pending-иконки: чтение ref в рендере React Compiler запрещает.
	const setDesiredPlaying = useCallback((value: boolean) => {
		desiredPlayingRef.current = value;
		setDesiredPlayingState(value);
	}, []);
	// 401 уже восстановил позицию: серверный resume отключаем до смены
	// трека/нового ручного запуска, не привязываясь к mediaId.
	const [resumeDisabled, setResumeDisabled] = useState(false);
	const resumePreemptedRef = useRef(false);
	const resetResumeGuards = () => {
		resumePreemptedRef.current = false;
		setResumeDisabled(false);
	};
	const sourceReady =
		current !== null && isSourceLoaded(current.id) && status.isLoaded;
	const progress = useAudioProgress({
		mediaId: current?.id ?? 0,
		generation: sourceGeneration,
		player,
		sourceReady,
		sourceLoading,
		resumeDisabled,
		resumePreemptedRef,
	});
	const { handleSeek, markUserStarted, resetUserStarted } = progress;

	const changeTrack = (next: AudioQueueState, play: boolean) => {
		const media = currentMedia(next);
		if (media === null) {
			return;
		}
		markUserAction();
		resetResumeGuards();
		resetUserStarted();
		setQueueState(next);
		setDesiredPlaying(play);
		loadSource(media, { play: () => desiredPlayingRef.current });
	};

	useAudioArtistSync(
		queueState,
		setQueueState,
		current,
		player,
		isSourceLoaded,
	);

	const controls = useAudioQueueControls({
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
	});

	// Незаконченный аудиотрек при пустой очереди: mini-player на паузе.
	const continueAudio = useContinueWatching("audio");
	const audioRestoredRef = useRef(false);
	useEffect(() => {
		if (!queueHydrated || audioRestoredRef.current) {
			return;
		}
		if (queueState.items.length > 0) {
			audioRestoredRef.current = true;
			return;
		}
		const entry = continueAudio.data?.[0];
		if (entry === undefined) {
			return;
		}
		audioRestoredRef.current = true;
		controls.restoreQueue([entry.media], 0);
	}, [continueAudio.data, controls, queueHydrated, queueState.items.length]);

	const editing = useAudioQueueEditing({
		queueState,
		setQueueState,
		setPlayed,
		desiredPlayingRef,
		changeTrack,
		unloadSource,
		markUserAction,
		resetUserStarted,
		setDesiredPlaying,
	});

	// Внешняя пауза (шторка, наушники, потеря аудиофокуса) приходит только
	// через status. Подтягиваем намерение по timeControlStatus: "paused" —
	// реальная пауза даже при isBuffering, а ожидание буферизации начатого
	// play намерение сохраняет. Иначе один тап play после шторки был бы no-op.
	useEffect(() => {
		if (status.didJustFinish) {
			return;
		}
		setDesiredPlaying(
			desiredAfterStatus({
				playing: status.playing,
				loading: sourceLoading,
				buffering: status.isBuffering,
				timeControlStatus: status.timeControlStatus,
				desiredPlaying: desiredPlayingRef.current,
			}),
		);
	}, [
		setDesiredPlaying,
		sourceLoading,
		status.didJustFinish,
		status.isBuffering,
		status.playing,
		status.timeControlStatus,
	]);

	// Один аудиосеанс на приложение: фон и lock screen требуют doNotMix.
	useEffect(() => {
		setAudioModeAsync({
			playsInSilentMode: true,
			shouldPlayInBackground: true,
			interruptionMode: "doNotMix",
		}).catch((error: unknown) => {
			console.warn("flux-audio: не удалось настроить аудиорежим", error);
		});
	}, []);

	// Ошибка плеера (включая 401): один preflight в общий слой, затем
	// повторная загрузка источника с актуальным Bearer.
	const handlePlaybackError = () => {
		// Ошибка старого источника после смены трека не должна тратить
		// единственный preflight нового.
		if (current === null || !isSourceLoaded(current.id)) {
			return;
		}
		const position = Number.isFinite(player.currentTime)
			? player.currentTime
			: 0;
		// 401@0: ничего не проиграно — новая generation должна сделать
		// fetchProgress и применить resume. 401@>0 восстанавливает позицию
		// сама 401-ветка, server-resume уступает.
		if (shouldPreemptResumeOn401(position)) {
			resumePreemptedRef.current = true;
			setResumeDisabled(true);
		} else {
			resetResumeGuards();
		}
		recoverSource(current, {
			play: () => desiredPlayingRef.current,
			position,
		});
	};

	useEventListener(player, "playbackStatusUpdate", (event) => {
		if (event.didJustFinish) {
			controls.finish();
		}
		if (event.error !== null) {
			handlePlaybackError();
		}
	});

	// Выход из аккаунта и смена сервера не оставляют очередь прошлого
	// пользователя/origin. Событие эмитится только на переходе user → null,
	// поэтому холодный старт без входа сохранённую очередь не стирает.
	useLocalReset(() => {
		audioRestoredRef.current = false;
		editing.clear();
	});

	const seek = useAudioSeek(player, handleSeek, markUserStarted);

	const actions: AudioActions = {
		...controls,
		...editing,
		seek,
		cycleRate,
	};
	const stableActions = useStableAudioActions(actions);

	const duration =
		status.duration > 0 ? status.duration : (current?.duration ?? 0);
	const state: AudioState = {
		queue: queueState.items,
		index: queueState.index,
		current,
		displayPlaying:
			status.playing ||
			(desiredPlaying && (sourceLoading || status.isBuffering)),
		currentTime: status.currentTime,
		duration,
		shuffle,
		repeat,
		error: sourceFailed ? t("audio.player.error") : null,
		loading: sourceLoading,
		buffering: status.isBuffering,
		rate,
	};

	return (
		<AudioActionsContext.Provider value={stableActions}>
			<AudioStateContext.Provider value={state}>
				{children}
			</AudioStateContext.Provider>
		</AudioActionsContext.Provider>
	);
}

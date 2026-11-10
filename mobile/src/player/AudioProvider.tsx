import {
	type AudioQueueState,
	currentMedia,
	emptyQueue,
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
	useRef,
	useState,
} from "react";
import { useSession } from "../auth/session";
import { t, useLanguage } from "../i18n";
import { desiredAfterStatus } from "./audioPlaybackPolicy";
import {
	clearAudioQueue,
	loadAudioQueue,
	saveAudioQueue,
} from "./audioQueueStorage";
import {
	type AudioControls,
	useAudioQueueControls,
} from "./useAudioQueueControls";
import {
	type AudioQueueEditing,
	useAudioQueueEditing,
} from "./useAudioQueueEditing";
import { useAudioSource } from "./useAudioSource";

// 500 мс — дефолт expo-audio: мини-бару хватает, лишних перерисовок нет.
const STATUS_UPDATE_INTERVAL_MS = 500;

export interface AudioPlayerContextValue
	extends AudioControls,
		AudioQueueEditing {
	queue: Media[];
	index: number;
	current: Media | null;
	playing: boolean;
	currentTime: number;
	duration: number;
	shuffle: boolean;
	repeat: RepeatMode;
	error: string | null;
	seek: (seconds: number) => void;
}

const AudioPlayerContext = createContext<AudioPlayerContextValue | null>(null);

export function useAudioPlayer(): AudioPlayerContextValue {
	const value = useContext(AudioPlayerContext);
	if (value === null) {
		throw new Error("useAudioPlayer must be used inside AudioProvider");
	}
	return value;
}

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
	const {
		failed: sourceFailed,
		loading: sourceLoading,
		load: loadSource,
		recover: recoverSource,
		unload: unloadSource,
		isLoaded: isSourceLoaded,
	} = useAudioSource(player);
	const desiredPlayingRef = useRef(false);

	const [queueState, setQueueState] = useState<AudioQueueState>(emptyQueue);
	const [played, setPlayed] = useState<ReadonlySet<number>>(new Set());
	const [shuffle, setShuffle] = useState(false);
	const [repeat, setRepeat] = useState<RepeatMode>("off");
	const [hydrated, setHydrated] = useState(false);

	const current = currentMedia(queueState);

	// Восстановление не запускает воспроизведение: источник подставится
	// только когда пользователь нажмёт play или выберет другой трек.
	useEffect(() => {
		let active = true;
		void loadAudioQueue().then((restored) => {
			if (!active) {
				return;
			}
			if (restored !== null) {
				setQueueState(restored.queue);
				setPlayed(restored.played);
				setShuffle(restored.shuffle);
				setRepeat(restored.repeat);
			}
			setHydrated(true);
		});
		return () => {
			active = false;
		};
	}, []);

	const changeTrack = useCallback(
		(next: AudioQueueState, play: boolean) => {
			const media = currentMedia(next);
			if (media === null) {
				return;
			}
			setQueueState(next);
			desiredPlayingRef.current = play;
			loadSource(media, { play: () => desiredPlayingRef.current });
		},
		[loadSource],
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
	});

	const editing = useAudioQueueEditing({
		queueState,
		setQueueState,
		setPlayed,
		desiredPlayingRef,
		changeTrack,
		unloadSource,
	});

	// Очередь/режимы пишутся одним ключом, пока очередь не пуста. Пустую
	// очередь не храним: после clear рестарт не должен воскрешать трек.
	useEffect(() => {
		if (!hydrated) {
			return;
		}
		if (queueState.items.length === 0) {
			void clearAudioQueue();
			return;
		}
		void saveAudioQueue({ queue: queueState, played, shuffle, repeat });
	}, [hydrated, played, queueState, repeat, shuffle]);

	// Внешняя пауза (шторка, наушники, потеря аудиофокуса) приходит только
	// через status. Подтягиваем намерение по timeControlStatus: "paused" —
	// реальная пауза даже при isBuffering, а ожидание буферизации начатого
	// play намерение сохраняет. Иначе один тап play после шторки был бы no-op.
	useEffect(() => {
		if (status.didJustFinish) {
			return;
		}
		desiredPlayingRef.current = desiredAfterStatus({
			playing: status.playing,
			loading: sourceLoading,
			buffering: status.isBuffering,
			timeControlStatus: status.timeControlStatus,
			desiredPlaying: desiredPlayingRef.current,
		});
	}, [
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
	const handlePlaybackError = useCallback(() => {
		// Ошибка старого источника после смены трека не должна тратить
		// единственный preflight нового.
		if (current === null || !isSourceLoaded(current.id)) {
			return;
		}
		const position = Number.isFinite(player.currentTime)
			? player.currentTime
			: 0;
		recoverSource(current, {
			play: () => desiredPlayingRef.current,
			position,
		});
	}, [current, isSourceLoaded, player, recoverSource]);

	useEventListener(player, "playbackStatusUpdate", (event) => {
		if (event.didJustFinish) {
			controls.finish();
		}
		if (event.error !== null) {
			handlePlaybackError();
		}
	});

	// Выход из аккаунта не оставляет очередь прошлого пользователя.
	// undefined — сессия ещё грузится (или упала сеть), тогда не трогаем.
	const session = useSession();
	const clearQueue = editing.clear;
	useEffect(() => {
		if (hydrated && session.data === null) {
			clearQueue();
		}
	}, [clearQueue, hydrated, session.data]);

	// seekTo оставлен в провайдере: полный плеер Task 13 использует его
	// без обращений к нативному AudioPlayer из UI.
	const seek = useCallback(
		(seconds: number) => {
			if (!Number.isFinite(seconds)) {
				return;
			}
			void player.seekTo(Math.max(0, seconds)).catch(() => {
				// Источник ещё не загружен: seek применится при следующем play.
			});
		},
		[player],
	);

	const duration =
		status.duration > 0 ? status.duration : (current?.duration ?? 0);
	const value: AudioPlayerContextValue = {
		...controls,
		...editing,
		queue: queueState.items,
		index: queueState.index,
		current,
		playing: status.playing,
		currentTime: status.currentTime,
		duration,
		shuffle,
		repeat,
		error: sourceFailed ? t("audio.player.error") : null,
		seek,
	};

	return (
		<AudioPlayerContext.Provider value={value}>
			{children}
		</AudioPlayerContext.Provider>
	);
}

import {
	type AudioQueueState,
	currentMedia,
	emptyQueue,
	type RepeatMode,
} from "@flux/shared";
import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useEffect,
	useRef,
	useState,
} from "react";
import { useTranslation } from "react-i18next";
import { apiFetch } from "../../api/client";
import { fetchLatestUnfinishedAudio } from "../../api/progress";
import { useSession } from "../../api/session";
import type { Media } from "../../core/media";
import { useMediaProgress } from "../media/useMediaProgress";
import { PLAYBACK_ERROR } from "./audioPlayback";
import { HiddenAudio } from "./HiddenAudio";
import { loadPersistedQueue, loadPersistedSettings } from "./playerPersistence";
import { useAudioElementSync } from "./useAudioElementSync";
import { useAudioMediaSession } from "./useAudioMediaSession";
import { useAudioTimings } from "./useAudioTimings";
import { usePlaybackControls } from "./usePlaybackControls";
import { usePlayerPersistence } from "./usePlayerPersistence";
import { useTrackEnded } from "./useTrackEnded";

interface AudioPlayerContextValue {
	queue: Media[];
	index: number;
	current: Media | null;
	playing: boolean;
	currentTime: number;
	duration: number;
	volume: number;
	shuffle: boolean;
	repeat: RepeatMode;
	error: string | null;
	playQueue: (items: Media[], startIndex?: number) => void;
	playMedia: (media: Media) => void;
	enqueue: (media: Media) => void;
	toggle: () => void;
	next: () => void;
	previous: () => void;
	select: (index: number) => void;
	seek: (time: number) => void;
	setVolume: (volume: number) => void;
	toggleShuffle: () => void;
	cycleRepeat: () => void;
	move: (from: number, to: number) => void;
	removeAt: (index: number) => void;
	clear: () => void;
}

const AudioPlayerContext = createContext<AudioPlayerContextValue | null>(null);

export function useAudioPlayer(): AudioPlayerContextValue {
	const context = useContext(AudioPlayerContext);
	if (context === null) {
		throw new Error("useAudioPlayer must be used inside AudioPlayerProvider");
	}
	return context;
}

export function AudioPlayerProvider({ children }: { children: ReactNode }) {
	const { t } = useTranslation();
	// Внутренний сентинел audioPlayback: пользователь видит перевод.
	const playbackFailed = t("player.errorBody");
	// Начальное состояние — из localStorage (очередь переживает
	// перезагрузку). Очередь и настройки грузятся независимо: громкость
	// и режимы — предпочтения, они действуют и без очереди.
	// Автоплей не восстанавливаем: браузеры его всё равно
	// режут, а сохранённая серверная позиция подтянется при старте.
	const [restoredQueue] = useState(loadPersistedQueue);
	const [restoredSettings] = useState(loadPersistedSettings);
	const [queueState, setQueueState] = useState<AudioQueueState>(
		restoredQueue?.queue ?? emptyQueue,
	);
	const queue = queueState.items;
	const index = queueState.index;
	const [playing, setPlaying] = useState(false);
	const [volume, setVolumeState] = useState(restoredSettings.volume);
	const [shuffle, setShuffle] = useState(restoredSettings.shuffle);
	const [repeat, setRepeat] = useState<RepeatMode>(restoredSettings.repeat);
	const [error, setError] = useState<string | null>(null);
	const [sourceNonce, setSourceNonce] = useState(0);
	const reloadTried = useRef(false);
	const audioRef = useRef<HTMLAudioElement | null>(null);
	const shouldPlay = useRef(false);
	const current = currentMedia(queueState);
	const currentId = current?.id ?? 0;
	useEffect(() => {
		reloadTried.current = false;
	}, [currentId]);
	const timings = useAudioTimings(currentId);
	// Допуск дрейфа автоплея: трек уже играет, пока позиция едет с сервера.
	const progress = useMediaProgress(currentId, audioRef, current !== null, 2);
	const handlePlayError = useCallback(
		(message: string) => {
			setError(message === PLAYBACK_ERROR ? playbackFailed : message);
			setPlaying(false);
		},
		[playbackFailed],
	);
	// Один раз пробуем восстановить аудиопоток после истечения access-куки:
	// apiFetch обновит сессию, затем перемонтируем <audio> с новым query.
	const retryAudio = useCallback(() => {
		if (current === null || reloadTried.current) {
			handlePlayError(PLAYBACK_ERROR);
			return;
		}
		reloadTried.current = true;
		void apiFetch(`/media/${current.id}`).then(
			() => setSourceNonce((value) => value + 1),
			() => handlePlayError(PLAYBACK_ERROR),
		);
	}, [current, handlePlayError]);

	// Сид мини-плеера: без очереди (и без сохранённой) подтягиваем
	// последний недослушанный трек с сервера — на паузе, позиция
	// восстановится прогрессом при загрузке метаданных. Применяем
	// функцией: пользователь мог начать очередь, пока запрос в воздухе.
	const seeded = useRef(restoredQueue !== null);
	useEffect(() => {
		if (seeded.current || queue.length > 0) {
			return;
		}
		seeded.current = true;
		void fetchLatestUnfinishedAudio().then((media) => {
			if (media === null) {
				return;
			}
			setQueueState((prev) =>
				prev.items.length === 0 ? { items: [media], index: 0 } : prev,
			);
		});
	}, [queue.length]);

	const toggleShuffle = useCallback(() => {
		setShuffle((prev) => !prev);
	}, []);

	const cycleRepeat = useCallback(() => {
		setRepeat((prev) =>
			prev === "off" ? "all" : prev === "all" ? "one" : "off",
		);
	}, []);

	const controls = usePlaybackControls({
		queueState,
		setQueueState,
		current,
		currentId,
		audioRef,
		shouldPlayRef: shouldPlay,
		shuffle,
		repeat,
		progress,
		markTime: timings.markTime,
		setError,
		setPlaying,
		setVolumeState,
		onPlayError: handlePlayError,
		initialPlayed: restoredQueue?.played,
	});

	const handleTrackEnded = useTrackEnded({
		repeat,
		audioRef,
		markTime: timings.markTime,
		next: controls.next,
		onProgressEnded: progress.handleEnded,
		onError: handlePlayError,
	});

	useAudioElementSync({
		current,
		volume,
		audioRef,
		shouldPlay,
		onError: handlePlayError,
	});

	usePlayerPersistence({
		queueState,
		played: controls.played,
		volume,
		shuffle,
		repeat,
	});

	// Приватность очереди: провайдер смонтирован выше Outlet и переживает
	// logout, поэтому при пустой сессии сносим очередь прошлого
	// пользователя полным clear (стоп + чистка персиста). undefined —
	// загрузка: ошибки сессия бросает, а не кэширует null. clear сессию
	// не трогает, эффект зависит только от фронта в null — зацикливания
	// нет. Эффект после персиста: при старте без сессии восстановленная
	// из storage очередь сначала пересохраняется, затем сносится.
	const { data: session } = useSession();
	const { clear } = controls;
	useEffect(() => {
		if (session === null) {
			clear();
		}
	}, [session, clear]);

	useAudioMediaSession({
		current,
		currentTime: timings.currentTime,
		duration: timings.duration,
		onToggle: controls.toggle,
		next: controls.next,
		previous: controls.previous,
	});

	return (
		<AudioPlayerContext.Provider
			value={{
				queue,
				index,
				current,
				playing,
				currentTime: timings.currentTime,
				duration: timings.duration,
				volume,
				shuffle,
				repeat,
				error,
				...controls,
				toggleShuffle,
				cycleRepeat,
			}}
		>
			{children}
			<HiddenAudio
				audioRef={audioRef}
				src={
					current === null
						? undefined
						: `/api/media/${current.id}/stream?retry=${sourceNonce}`
				}
				onLoadedMetadata={(event) => {
					timings.markLoaded(event.currentTarget.duration || 0);
					progress.handleLoadedMetadata();
				}}
				onTimeUpdate={(event) => {
					timings.markTime(event.currentTarget.currentTime);
					progress.handleTimeUpdate();
				}}
				onSeeked={(event) => {
					// Восстановление позиции на паузе: timeupdate не стреляет.
					timings.markTime(event.currentTarget.currentTime);
				}}
				onPlay={() => setPlaying(true)}
				onPause={() => setPlaying(false)}
				onEnded={handleTrackEnded}
				onError={retryAudio}
			/>
		</AudioPlayerContext.Provider>
	);
}

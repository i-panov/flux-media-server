import {
	createContext,
	type ReactNode,
	useCallback,
	useContext,
	useRef,
	useState,
} from "react";
import type { Media } from "../../core/media";
import { useMediaProgress } from "../media/useMediaProgress";
import { PLAYBACK_ERROR, playAudio } from "./audioPlayback";
import {
	type AudioQueueState,
	currentMedia,
	emptyQueue,
	removeTrack,
	selectIndex,
	startQueue,
} from "./audioQueue";
import { HiddenAudio } from "./HiddenAudio";
import { useAudioElementSync } from "./useAudioElementSync";
import { useAudioMediaSession } from "./useAudioMediaSession";

interface AudioPlayerContextValue {
	queue: Media[];
	index: number;
	current: Media | null;
	playing: boolean;
	currentTime: number;
	duration: number;
	volume: number;
	error: string | null;
	playQueue: (items: Media[], startIndex?: number) => void;
	playMedia: (media: Media) => void;
	toggle: () => void;
	next: () => void;
	previous: () => void;
	select: (index: number) => void;
	seek: (time: number) => void;
	setVolume: (volume: number) => void;
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
	const [queueState, setQueueState] = useState<AudioQueueState>(emptyQueue);
	const queue = queueState.items;
	const index = queueState.index;
	const [playing, setPlaying] = useState(false);
	// Позиция и длительность привязаны к id трека: после переключения
	// старые значения к новому файлу не относятся, а сбрасывать их
	// эффектом не нужно — сравнение с currentId даёт ноль само.
	const [time, setTime] = useState({ mediaId: 0, seconds: 0 });
	const [loaded, setLoaded] = useState({ mediaId: 0, seconds: 0 });
	const [volume, setVolumeState] = useState(1);
	const [error, setError] = useState<string | null>(null);
	const audioRef = useRef<HTMLAudioElement | null>(null);
	const shouldPlay = useRef(false);
	const current = currentMedia(queueState);
	const currentId = current?.id ?? 0;
	const currentTime = time.mediaId === currentId ? time.seconds : 0;
	const duration = loaded.mediaId === currentId ? loaded.seconds : 0;
	const progress = useMediaProgress(currentId, audioRef, current !== null);
	const handlePlayError = useCallback((message: string) => {
		setError(message);
		setPlaying(false);
	}, []);

	const playQueue = useCallback(
		(items: Media[], startIndex = 0) => {
			if (items.length === 0) {
				return;
			}
			const nextState = startQueue(items, startIndex);
			shouldPlay.current = true;
			setError(null);
			setQueueState(nextState);
			const element = audioRef.current;
			if (element !== null && currentMedia(nextState)?.id === currentId) {
				playAudio(element, handlePlayError);
			}
		},
		[currentId, handlePlayError],
	);

	const playMedia = useCallback(
		(media: Media) => playQueue([media], 0),
		[playQueue],
	);

	const toggle = useCallback(() => {
		const element = audioRef.current;
		if (element === null || current === null) {
			return;
		}
		if (element.paused) {
			shouldPlay.current = true;
			// Повтор после сбоя: старая ошибка не должна висеть, если
			// воспроизведение на этот раз пошло.
			setError(null);
			playAudio(element, handlePlayError);
		} else {
			progress.handlePause();
			shouldPlay.current = false;
			element.pause();
		}
	}, [current, handlePlayError, progress]);

	const select = useCallback(
		(nextIndex: number) => {
			if (nextIndex < 0 || nextIndex >= queue.length) {
				return;
			}
			shouldPlay.current = true;
			setError(null);
			setQueueState((prev) => selectIndex(prev, nextIndex));
		},
		[queue.length],
	);

	const next = useCallback(() => {
		if (index < queue.length - 1) {
			select(index + 1);
			return;
		}
		shouldPlay.current = false;
		progress.handlePause();
		audioRef.current?.pause();
	}, [index, progress, queue.length, select]);

	const previous = useCallback(() => {
		const element = audioRef.current;
		if (element !== null && element.currentTime > 3) {
			element.currentTime = 0;
			setTime({ mediaId: currentId, seconds: 0 });
			return;
		}
		if (index > 0) {
			select(index - 1);
		}
	}, [currentId, index, select]);

	const seek = useCallback(
		(seconds: number) => {
			const element = audioRef.current;
			if (element === null) {
				return;
			}
			element.currentTime = seconds;
			setTime({ mediaId: currentId, seconds });
		},
		[currentId],
	);

	const setVolume = useCallback((value: number) => {
		const normalized = Math.min(Math.max(value, 0), 1);
		setVolumeState(normalized);
		if (audioRef.current !== null) {
			audioRef.current.volume = normalized;
		}
	}, []);

	const clear = useCallback(() => {
		shouldPlay.current = false;
		const element = audioRef.current;
		if (element !== null) {
			element.pause();
			element.removeAttribute("src");
			element.load();
		}
		setQueueState(emptyQueue);
		setPlaying(false);
		setError(null);
	}, []);

	const removeAt = useCallback(
		(removeIndex: number) => {
			if (removeIndex < 0 || removeIndex >= queue.length) {
				return;
			}
			if (queue.length === 1) {
				clear();
				return;
			}
			shouldPlay.current = true;
			setQueueState((prev) => removeTrack(prev, removeIndex));
		},
		[clear, queue.length],
	);

	useAudioElementSync({
		current,
		volume,
		audioRef,
		shouldPlay,
		onError: handlePlayError,
	});

	useAudioMediaSession({
		current,
		currentTime,
		duration,
		onToggle: toggle,
		next,
		previous,
	});

	return (
		<AudioPlayerContext.Provider
			value={{
				queue,
				index,
				current,
				playing,
				currentTime,
				duration,
				volume,
				error,
				playQueue,
				playMedia,
				toggle,
				next,
				previous,
				select,
				seek,
				setVolume,
				removeAt,
				clear,
			}}
		>
			{children}
			<HiddenAudio
				audioRef={audioRef}
				src={current === null ? undefined : `/api/media/${current.id}/stream`}
				onLoadedMetadata={(event) => {
					setLoaded({
						mediaId: currentId,
						seconds: event.currentTarget.duration || 0,
					});
					progress.handleLoadedMetadata();
				}}
				onTimeUpdate={(event) => {
					setTime({
						mediaId: currentId,
						seconds: event.currentTarget.currentTime,
					});
					progress.handleTimeUpdate();
				}}
				onPlay={() => setPlaying(true)}
				onPause={() => setPlaying(false)}
				onEnded={() => {
					progress.handleEnded();
					next();
				}}
				onError={() => {
					setError(PLAYBACK_ERROR);
					setPlaying(false);
				}}
			/>
		</AudioPlayerContext.Provider>
	);
}

import { deleteProgress, saveProgress } from "@flux/shared";
import { useEventListener } from "expo";
import type { AudioPlayer } from "expo-audio";
import { useCallback, useEffect, useRef } from "react";
import { useInvalidateContinueWatching } from "../api/progress";
import {
	buildProgressPayload,
	RESET_POSITION_SECONDS,
	shouldDeleteProgress,
	shouldSaveProgress,
} from "./videoProgress";

interface UseAudioProgressTrackingOptions {
	/** Текущий трек; 0 — очередь пуста. */
	mediaId: number;
	player: AudioPlayer;
	/** Источник загружен и готов принимать seek. */
	sourceReady: boolean;
	/** Идёт замена/перечитывание источника: status-события не сохраняем. */
	sourceLoading: boolean;
}

export interface AudioProgressTracking {
	/** Сообщить хуку о ручном seek: возврат в 0 удаляет прогресс. */
	handleSeek: (seconds: number) => void;
	/** Пользователь уже запускал текущий трек/делал seek (для resume). */
	userStarted: () => boolean;
	/** Осознанное действие пользователя: play, seek, выбор трека. */
	markUserStarted: () => void;
	/** Сбросить намерение при смене трека/очистке очереди. */
	resetUserStarted: () => void;
	/** Применить серверную позицию к прогрессу/UI до seek. */
	onResumed: (target: number, duration: number) => void;
}

// PUT/DELETE сериализуем: иначе поздний PUT после reset воскресил бы
// удалённую запись. После успеха чистим ряд «Продолжить».
function chainProgressWrite(
	chain: Promise<unknown>,
	write: () => Promise<unknown>,
	refresh: () => void,
	onError?: () => void,
): Promise<unknown> {
	return chain
		.then(write)
		.then(refresh)
		.catch(() => {
			onError?.();
		});
}

// Намерение пользователя (play/seek/выбор трека) живёт отдельным хуком:
// он нужен и трекингу, и эффекту смены трека.
function useUserStarted(): {
	userStarted: () => boolean;
	markUserStarted: () => void;
	resetUserStarted: () => void;
} {
	const started = useRef(false);
	const userStarted = useCallback(() => started.current, []);
	const markUserStarted = useCallback(() => {
		started.current = true;
	}, []);
	const resetUserStarted = useCallback(() => {
		started.current = false;
	}, []);
	return { userStarted, markUserStarted, resetUserStarted };
}

// Сохранение аудиопрогресса: те же shared-функции и пороги, что у видео.
// Пишем каждые 5 секунд воспроизведения, на паузе, при смене/выгрузке
// трека и в конце; completed считает buildProgressPayload по порогу 90%.
export function useAudioProgressTracking({
	mediaId,
	player,
	sourceReady,
	sourceLoading,
}: UseAudioProgressTrackingOptions): AudioProgressTracking {
	const refreshContinue = useInvalidateContinueWatching("audio");
	// Автоплей/выбор трека не считаются действием пользователя.
	const { userStarted, markUserStarted, resetUserStarted } = useUserStarted();
	const trackedIdRef = useRef<number | null>(null);
	const sourceReadyRef = useRef(sourceReady);
	const sourceLoadingRef = useRef(sourceLoading);
	const lastPosition = useRef(0);
	const lastDuration = useRef(0);
	const lastSavedPosition = useRef(-1);
	const lastSavedAt = useRef<number | null>(null);
	const hasPlayed = useRef(false);
	const ended = useRef(false);
	const wasPlaying = useRef(false);
	const wasAwayFromStart = useRef(false);
	const resetSent = useRef(false);
	// PUT/DELETE прогресса сериализуем: иначе поздний PUT после reset
	// воскресил бы только что удалённую запись.
	const writeChain = useRef<Promise<unknown>>(Promise.resolve());

	useEffect(() => {
		sourceReadyRef.current = sourceReady;
		sourceLoadingRef.current = sourceLoading;
	}, [sourceLoading, sourceReady]);

	// Только refs: функция вызывается из нативного события, cleanup и смены
	// трека, поэтому не должна зависеть от render-состояния.
	const persistFor = useCallback(
		(trackId: number, position: number, duration: number, force: boolean) => {
			const payload = buildProgressPayload(trackId, position, duration);
			const now = Date.now();
			const save = shouldSaveProgress({
				position: payload.position,
				duration: payload.duration,
				now,
				lastSavedAt: lastSavedAt.current,
				lastSavedPosition: lastSavedPosition.current,
				force,
				ended: ended.current,
			});
			if (!save) {
				return;
			}
			// Отметки до запроса: параллельные события не порождают дубль PUT.
			lastSavedPosition.current = payload.position;
			lastSavedAt.current = now;
			resetSent.current = false;
			writeChain.current = chainProgressWrite(
				writeChain.current,
				() => saveProgress(payload),
				refreshContinue,
			);
		},
		[refreshContinue],
	);

	const removeProgressFor = useCallback(
		async (trackId: number) => {
			if (resetSent.current) {
				return;
			}
			resetSent.current = true;
			lastSavedPosition.current = 0;
			lastSavedAt.current = Date.now();
			const task = chainProgressWrite(
				writeChain.current,
				() => deleteProgress(trackId),
				refreshContinue,
				() => {
					resetSent.current = false;
				},
			);
			writeChain.current = task;
			await task;
		},
		[refreshContinue],
	);

	// Ноль после playback — reset (паритет с видео): DELETE, а не PUT 0.
	const notePosition = useCallback(
		(position: number) => {
			if (position > RESET_POSITION_SECONDS) {
				wasAwayFromStart.current = true;
				return;
			}
			const trackId = trackedIdRef.current;
			if (trackId === null) {
				return;
			}
			const remove = shouldDeleteProgress({
				position,
				playedOnce: hasPlayed.current,
				wasAwayFromStart: wasAwayFromStart.current,
				ended: ended.current,
				alreadyDeleted: resetSent.current,
			});
			if (remove) {
				void removeProgressFor(trackId);
			}
		},
		[removeProgressFor],
	);

	const handleSeek = useCallback(
		(seconds: number) => {
			const position = Number.isFinite(seconds) ? Math.max(seconds, 0) : 0;
			lastPosition.current = position;
			notePosition(position);
		},
		[notePosition],
	);

	useEventListener(player, "playbackStatusUpdate", (event) => {
		if (
			sourceLoadingRef.current ||
			!sourceReadyRef.current ||
			trackedIdRef.current === null
		) {
			return;
		}
		const trackId = trackedIdRef.current;
		const current = Number.isFinite(event.currentTime)
			? Math.max(event.currentTime, 0)
			: 0;
		const duration =
			Number.isFinite(event.duration) && event.duration > 0
				? event.duration
				: lastDuration.current;
		lastPosition.current = current;
		if (duration > 0) {
			lastDuration.current = duration;
		}
		if (event.didJustFinish) {
			const total = duration > 0 ? duration : lastDuration.current;
			if (total <= 0) {
				return;
			}
			lastPosition.current = total;
			lastDuration.current = total;
			ended.current = true;
			// Автоматический seek в 0 после end — не ручной reset.
			wasAwayFromStart.current = false;
			persistFor(trackId, total, total, true);
			return;
		}
		if (event.playing) {
			hasPlayed.current = true;
			wasPlaying.current = true;
			// После end повторный play снова должен сохранять тики.
			ended.current = false;
		}
		notePosition(current);
		if (event.playing) {
			persistFor(trackId, current, duration, false);
			return;
		}
		if (wasPlaying.current && !ended.current) {
			wasPlaying.current = false;
			persistFor(trackId, current, duration, true);
		}
	});

	// Смена трека: сохраняем позицию предыдущего и обнуляем состояние,
	// чтобы его 30-я секунда не приклеилась к следующему треку.
	useEffect(() => {
		const previous = trackedIdRef.current;
		if (previous !== null && previous !== mediaId) {
			if (hasPlayed.current && !ended.current) {
				persistFor(previous, lastPosition.current, lastDuration.current, true);
			}
			lastPosition.current = 0;
			lastDuration.current = 0;
			lastSavedPosition.current = -1;
			lastSavedAt.current = null;
			hasPlayed.current = false;
			ended.current = false;
			wasPlaying.current = false;
			wasAwayFromStart.current = false;
			resetSent.current = false;
			resetUserStarted();
		}
		trackedIdRef.current = mediaId;
	}, [mediaId, persistFor, resetUserStarted]);

	// Уход с экрана/закрытие приложения: последняя измеренная позиция.
	useEffect(() => {
		return () => {
			const trackId = trackedIdRef.current;
			if (trackId === null || !hasPlayed.current || ended.current) {
				return;
			}
			persistFor(trackId, lastPosition.current, lastDuration.current, true);
		};
	}, [persistFor]);

	const onResumed = useCallback(
		(target: number, duration: number) => {
			lastPosition.current = target;
			wasAwayFromStart.current = true;
			lastDuration.current = duration > 0 ? duration : lastDuration.current;
			const payload = buildProgressPayload(mediaId, target, duration);
			lastSavedPosition.current = payload.position;
			lastSavedAt.current = Date.now();
		},
		[mediaId],
	);

	return {
		handleSeek,
		userStarted,
		markUserStarted,
		resetUserStarted,
		onResumed,
	};
}

import { deleteProgress, fetchProgress, saveProgress } from "@flux/shared";
import { useEventListener } from "expo";
import type { VideoPlayer as NativeVideoPlayer } from "expo-video";
import { useCallback, useEffect, useRef, useState } from "react";
import { seekPlayer } from "./videoControls";
import {
	buildProgressPayload,
	RESET_POSITION_SECONDS,
	resumePosition,
	shouldDeleteProgress,
	shouldSaveProgress,
} from "./videoProgress";

interface UseVideoProgressOptions {
	mediaId: number;
	player: NativeVideoPlayer;
	/** Источник загружен: только с этого момента позиция валидна. */
	sourceReady: boolean;
	/** Пользователь уже запускал playback (в т.ч. после 401). */
	hasStarted: boolean;
	/** 401-ветка useVideoSource уже восстановила позицию: серверный resume нельзя. */
	resumeDisabled?: boolean;
	/** Синхронизировать UI с позицией, восстановленной с сервера. */
	onPositionRestored?: (seconds: number) => void;
}

interface VideoProgressState {
	/** Удалить серверный прогресс и вернуть playback в начало. */
	reset: () => Promise<void>;
	/** Сообщить хуку о ручном seek: возврат в 0 удаляет прогресс. */
	handleSeek: (seconds: number) => void;
	/** Серверная позиция была восстановлена (маркер для Maestro). */
	resumed: boolean;
}

// Прогресс видео: загрузка/сохранение через shared API, resume один раз после
// loaded, троттлинг PUT и защита от перезаписи нулём. 401-восстановление
// остаётся в useVideoSource: здесь resume не применяется, если плеер уже
// сдвинут (currentPosition) или пользователь успел начать.
export function useVideoProgress({
	mediaId,
	player,
	sourceReady,
	hasStarted,
	resumeDisabled = false,
	onPositionRestored,
}: UseVideoProgressOptions): VideoProgressState {
	const [resumed, setResumed] = useState(false);
	const mountedRef = useRef(false);
	const sourceReadyRef = useRef(sourceReady);
	const hasStartedRef = useRef(hasStarted);
	const resumeDisabledRef = useRef(resumeDisabled);
	const lastPosition = useRef(0);
	const lastDuration = useRef(0);
	const lastSavedPosition = useRef(-1);
	const lastSavedAt = useRef<number | null>(null);
	const hasPlayed = useRef(false);
	const ended = useRef(false);
	const wasPlaying = useRef(false);
	const wasAwayFromStart = useRef(false);
	const resetSent = useRef(false);

	useEffect(() => {
		mountedRef.current = true;
		return () => {
			mountedRef.current = false;
		};
	}, []);

	useEffect(() => {
		sourceReadyRef.current = sourceReady;
	}, [sourceReady]);

	useEffect(() => {
		hasStartedRef.current = hasStarted;
	}, [hasStarted]);

	useEffect(() => {
		resumeDisabledRef.current = resumeDisabled;
	}, [resumeDisabled]);

	// Удаление прогресса: ручной reset или возврат в 0 после playback. force
	// нужен кнопке «Смотреть с начала» — она удаляет даже свежий 0.
	const removeProgress = useCallback(
		async (force = false) => {
			if (!force && resetSent.current) {
				return;
			}
			resetSent.current = true;
			lastSavedPosition.current = 0;
			lastSavedAt.current = Date.now();
			if (mountedRef.current) {
				setResumed(false);
			}
			try {
				await deleteProgress(mediaId);
			} catch {
				// Сеть не должна ломать плеер: запись удалится при следующей попытке.
				resetSent.current = false;
			}
		},
		[mediaId],
	);

	// persist вызывается из нативных событий и cleanup: только refs, чтобы
	// замыкание не зависело от render-состояния.
	const persist = useCallback(
		(position: number, duration: number, force: boolean) => {
			const payload = buildProgressPayload(mediaId, position, duration);
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
			// Отметки ставим до запроса: параллельные timeUpdate не должны
			// порождать второй PUT на ту же секунду.
			lastSavedPosition.current = payload.position;
			lastSavedAt.current = now;
			// Новый PUT снова создаёт запись: следующий возврат в 0 её удалит.
			resetSent.current = false;
			void saveProgress(payload).catch(() => {
				// Прогресс необязателен: следующий тик или pause попробует снова.
			});
		},
		[mediaId],
	);

	// Ноль после playback — reset (паритет с web): DELETE, а не PUT 0.
	const notePosition = useCallback(
		(position: number) => {
			if (position > RESET_POSITION_SECONDS) {
				wasAwayFromStart.current = true;
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
				void removeProgress();
			}
		},
		[removeProgress],
	);

	const handleSeek = useCallback(
		(seconds: number) => {
			const position = Number.isFinite(seconds) ? Math.max(seconds, 0) : 0;
			lastPosition.current = position;
			notePosition(position);
		},
		[notePosition],
	);

	useEventListener(player, "timeUpdate", ({ currentTime }) => {
		if (!sourceReadyRef.current) {
			return;
		}
		const current = Number.isFinite(currentTime) ? Math.max(currentTime, 0) : 0;
		lastPosition.current = current;
		// Возврат в начало после playback удаляет запись; обычный старт с 0 —
		// нет, потому что wasAwayFromStart ещё false.
		notePosition(current);
		const duration =
			Number.isFinite(player.duration) && player.duration > 0
				? player.duration
				: lastDuration.current;
		if (duration > 0) {
			lastDuration.current = duration;
		}
		// Пишем только во время playback: pause/unmount сохраняются отдельно,
		// а seek на паузе не должен превращаться в PUT каждые полсекунды.
		if (!player.playing || ended.current) {
			return;
		}
		persist(current, duration, false);
	});

	useEventListener(player, "sourceLoad", ({ duration }) => {
		if (Number.isFinite(duration) && duration > 0) {
			lastDuration.current = duration;
		}
	});

	useEventListener(player, "playingChange", ({ isPlaying }) => {
		if (isPlaying) {
			hasPlayed.current = true;
			hasStartedRef.current = true;
			// После end пользователь может запустить видео заново: новые тики
			// снова должны сохраняться.
			ended.current = false;
		} else if (wasPlaying.current && !ended.current) {
			persist(lastPosition.current, lastDuration.current, true);
		}
		wasPlaying.current = isPlaying;
	});

	useEventListener(player, "playToEnd", () => {
		const duration =
			Number.isFinite(player.duration) && player.duration > 0
				? player.duration
				: lastDuration.current;
		if (duration <= 0) {
			return;
		}
		// Финальную позицию берём из длительности: VideoPlayer сразу после
		// этого перематывает в 0, и currentTime читать уже нельзя.
		lastPosition.current = duration;
		lastDuration.current = duration;
		ended.current = true;
		// Автоматический seek в 0 после end — не ручной reset.
		wasAwayFromStart.current = false;
		persist(duration, duration, true);
	});

	// Уход с экрана: сохраняем последнюю измеренную позицию. Если playback не
	// запускался (или видео уже завершилось), ничего не пишем — 0 после end не
	// должен затирать completed.
	useEffect(() => {
		return () => {
			if (ended.current || !hasPlayed.current) {
				return;
			}
			persist(lastPosition.current, lastDuration.current, true);
		};
	}, [persist]);

	const applyResume = useCallback(
		(target: number, duration: number) => {
			seekPlayer(player, target);
			lastPosition.current = target;
			wasAwayFromStart.current = true;
			lastDuration.current = duration > 0 ? duration : lastDuration.current;
			// Позиция уже есть на сервере: не отправляем её сразу повторно.
			lastSavedPosition.current = buildProgressPayload(
				mediaId,
				target,
				duration,
			).position;
			lastSavedAt.current = Date.now();
			setResumed(true);
		},
		[mediaId, player],
	);

	// Resume строго один раз на загрузку источника: fetchProgress отдаёт null
	// на 404, поэтому отсутствие записи — это просто «некуда продолжать».
	useServerResume({
		mediaId,
		player,
		sourceReady,
		hasStartedRef,
		resumeDisabledRef,
		onResume: applyResume,
		onPositionRestored,
	});

	const reset = useCallback(async () => {
		ended.current = false;
		hasPlayed.current = player.playing;
		wasPlaying.current = player.playing;
		wasAwayFromStart.current = false;
		lastPosition.current = 0;
		seekPlayer(player, 0);
		// Кнопка reset удаляет запись даже если позиция уже 0.
		await removeProgress(true);
	}, [player, removeProgress]);

	return { handleSeek, reset, resumed };
}

interface ServerResumeOptions {
	mediaId: number;
	player: NativeVideoPlayer;
	sourceReady: boolean;
	hasStartedRef: { current: boolean };
	resumeDisabledRef: { current: boolean };
	onResume: (target: number, duration: number) => void;
	onPositionRestored?: (seconds: number) => void;
}

// Один fetch прогресса на загрузку источника. Отдельный хук держит
// useVideoProgress в пределах лимита и не смешивает resume с сохранением.
function useServerResume({
	mediaId,
	player,
	sourceReady,
	hasStartedRef,
	resumeDisabledRef,
	onResume,
	onPositionRestored,
}: ServerResumeOptions): void {
	const attempted = useRef(false);
	useEffect(() => {
		if (!sourceReady || attempted.current || resumeDisabledRef.current) {
			return;
		}
		let cancelled = false;
		const restore = async () => {
			try {
				const stored = await fetchProgress(mediaId);
				if (cancelled) {
					return;
				}
				const duration =
					Number.isFinite(player.duration) && player.duration > 0
						? player.duration
						: 0;
				const target = resumePosition(stored, {
					duration,
					currentPosition: Number.isFinite(player.currentTime)
						? player.currentTime
						: 0,
					// player.playing закрывает гонку: пользователь мог нажать Play
					// до того, как эффект обновил hasStartedRef.
					hasStarted: hasStartedRef.current || player.playing,
				});
				attempted.current = true;
				if (target === null) {
					return;
				}
				onResume(target, duration);
				onPositionRestored?.(target);
			} catch {
				// Сеть/401 не должны ломать playback: resume просто не состоялся.
				if (!cancelled) {
					attempted.current = true;
				}
			}
		};
		void restore();
		return () => {
			cancelled = true;
		};
	}, [
		hasStartedRef,
		mediaId,
		onPositionRestored,
		onResume,
		player,
		resumeDisabledRef,
		sourceReady,
	]);
}

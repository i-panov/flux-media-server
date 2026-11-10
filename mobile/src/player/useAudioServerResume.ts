import { fetchProgress } from "@flux/shared";
import type { AudioPlayer } from "expo-audio";
import { type RefObject, useEffect, useRef } from "react";
import { audioResumeTarget, shouldApplyResume } from "./audioProgress";

interface UseAudioServerResumeOptions {
	mediaId: number;
	/** Уникален для каждой загрузки/reload источника, даже с тем же mediaId. */
	generation: number;
	player: AudioPlayer;
	sourceReady: boolean;
	/** 401-ветка уже восстановила позицию: серверный resume не нужен. */
	resumeDisabled: boolean;
	/** Пользователь уже сделал ручной seek текущего трека. */
	userStarted: () => boolean;
	/** 401-ветка уже забрала seek: серверный resume не должен спорить. */
	resumePreemptedRef: RefObject<boolean>;
	/** Применить найденную позицию к прогрессу/UI до seek. */
	onResumed: (target: number, duration: number) => void;
}

// Один fetch прогресса на загрузку источника. Обычный выбор трека/play не
// считается вмешательством; resume отменяют ручной seek, поздний 401 и
// повторная попытка для той же generation.
export function useAudioServerResume({
	mediaId,
	generation,
	player,
	sourceReady,
	resumeDisabled,
	userStarted,
	resumePreemptedRef,
	onResumed,
}: UseAudioServerResumeOptions): void {
	const attemptedFor = useRef<number | null>(null);

	useEffect(() => {
		if (!sourceReady || resumeDisabled) {
			return;
		}
		if (attemptedFor.current === generation) {
			return;
		}
		attemptedFor.current = generation;
		// Снимаем намерение ДО await: автоплей после replace не должен
		// считаться действием пользователя.
		const userStartedBefore = userStarted();
		let cancelled = false;
		void (async () => {
			try {
				const stored = await fetchProgress(mediaId);
				if (
					cancelled ||
					!shouldApplyResume({
						userStartedBefore,
						userStartedAfter: userStarted(),
						preempted: resumePreemptedRef.current,
						progress: stored,
					})
				) {
					return;
				}
				const duration =
					Number.isFinite(player.duration) && player.duration > 0
						? player.duration
						: 0;
				// currentPosition сюда не передаём: пока шёл fetch, автоплей
				// мог уйти вперёд. Пользовательский seek уже отсечён gate выше.
				const target = audioResumeTarget(stored, {
					duration,
					currentPosition: 0,
					hasStarted: false,
				});
				if (target === null) {
					return;
				}
				onResumed(target, duration);
				await player.seekTo(target).catch(() => {
					// Источник мог выгрузиться — resume просто не применился.
				});
			} catch {
				// Сеть/401 не должны мешать playback.
			}
		})();
		return () => {
			cancelled = true;
		};
	}, [
		generation,
		mediaId,
		onResumed,
		player,
		resumeDisabled,
		resumePreemptedRef,
		sourceReady,
		userStarted,
	]);
}

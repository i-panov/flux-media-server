import type { AudioPlayer } from "expo-audio";
import type { RefObject } from "react";
import { useAudioProgressTracking } from "./useAudioProgressTracking";
import { useAudioServerResume } from "./useAudioServerResume";

interface UseAudioProgressOptions {
	/** Текущий трек; 0 — очередь пуста. */
	mediaId: number;
	/** Версия загрузки источника: reload того же id — новая generation. */
	generation: number;
	player: AudioPlayer;
	/** Источник загружен и готов принимать seek. */
	sourceReady: boolean;
	/** Идёт замена/перечитывание источника: status-события не сохраняем. */
	sourceLoading: boolean;
	/** 401-ветка уже восстановила позицию: серверный resume не нужен. */
	resumeDisabled?: boolean;
	/** 401-ветка уже забрала seek: серверный resume уступает. */
	resumePreemptedRef: RefObject<boolean>;
}

export interface AudioProgressState {
	/** Сообщить хуку о ручном seek: возврат в 0 удаляет прогресс. */
	handleSeek: (seconds: number) => void;
	/** Ручной seek/±10: отменяет поздний server-resume. */
	markUserStarted: () => void;
	/** Сбросить намерение при смене трека/очистке очереди. */
	resetUserStarted: () => void;
}

// Композиция прогресса: сохранение/сброс живёт в useAudioProgressTracking,
// одноразовый resume после loaded — в useAudioServerResume. Так оба хука
// остаются в лимите размера и не смешивают две зоны ответственности.
export function useAudioProgress({
	mediaId,
	generation,
	player,
	sourceReady,
	sourceLoading,
	resumeDisabled = false,
	resumePreemptedRef,
}: UseAudioProgressOptions): AudioProgressState {
	const {
		handleSeek,
		userStarted,
		markUserStarted,
		resetUserStarted,
		onResumed,
	} = useAudioProgressTracking({ mediaId, player, sourceReady, sourceLoading });
	useAudioServerResume({
		mediaId,
		generation,
		player,
		sourceReady,
		resumeDisabled,
		userStarted,
		resumePreemptedRef,
		onResumed,
	});
	return { handleSeek, markUserStarted, resetUserStarted };
}

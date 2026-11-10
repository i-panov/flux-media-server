import {
	type ResumeContext,
	resumePosition,
	type StoredProgress,
} from "./videoProgress";

export interface ResumeGate {
	/** Пользователь сделал seek до запроса прогресса. */
	userStartedBefore: boolean;
	/** Пользователь сделал seek, пока запрос был в полёте. */
	userStartedAfter: boolean;
	/** 401-ветка уже забрала seek: server-resume уступает. */
	preempted: boolean;
	progress: StoredProgress | null;
}

// 401 на позиции 0 не должен навсегда отключать server resume: плеер ещё
// ничего не проиграл, и восстановление из прогресса уместно. На позиции >0
// 401-ветка уже восстанавливает место сама.
export function shouldPreemptResumeOn401(position: number): boolean {
	return Number.isFinite(position) && position > 0;
}

// Решение «применять ли серверный resume» вынесено в чистую функцию.
// Обычный выбор трека/play не выставляет userStarted — resume должен
// сработать; отменяют его только ручной seek/±10 и 401-preemption.
export function shouldApplyResume({
	userStartedBefore,
	userStartedAfter,
	preempted,
	progress,
}: ResumeGate): boolean {
	return (
		!userStartedBefore && !userStartedAfter && !preempted && progress !== null
	);
}

// Аудиоплеер использует те же пороги, что и видео (5 секунд между PUT,
// 90% — completed, 0.5 секунды — reset). Здесь только правило resume,
// чтобы не дублировать константы в двух плеерах.
export function audioResumeTarget(
	progress: StoredProgress | null,
	context: ResumeContext,
): number | null {
	return resumePosition(progress, context);
}

import { formatDuration } from "@flux/shared";

// Порядок цикла кнопки скорости: от замедления к ускорению и обратно к 0.5.
export const PLAYBACK_SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 2] as const;

// formatDuration рассчитан на известную длительность: до загрузки источника
// плеер отдаёт NaN/Infinity, а в подписи таймлайна нужен нулевой отсчёт.
export function formatTime(seconds: number): string {
	if (!Number.isFinite(seconds) || seconds < 0) {
		return "0:00";
	}
	return formatDuration(seconds);
}

// Позиция после seek: текущая ± шаг, но не за пределами длительности.
// Неизвестная длительность (0/NaN) ограничивает только снизу, иначе seek
// в потоке без метаданных всегда возвращал бы 0.
export function clampSeek(
	position: number,
	delta: number,
	duration: number,
): number {
	if (!Number.isFinite(position) || !Number.isFinite(delta)) {
		return 0;
	}
	const target = position + delta;
	if (!Number.isFinite(duration) || duration <= 0) {
		return Math.max(0, target);
	}
	return Math.min(Math.max(target, 0), duration);
}

// Неизвестная скорость приходит от плеера после смены источника: цикл
// начинается с обычной 1×, а не с первого элемента списка.
export function nextPlaybackRate(current: number): number {
	const index = PLAYBACK_SPEEDS.indexOf(
		current as (typeof PLAYBACK_SPEEDS)[number],
	);
	if (index === -1) {
		return 1;
	}
	return PLAYBACK_SPEEDS[(index + 1) % PLAYBACK_SPEEDS.length];
}

// Нативный плеер мутируется только через такие внешние хелперы: React
// Compiler иначе считает запись в поле мутацией значения из хука.
export interface SeekTarget {
	currentTime: number;
}

export function seekPlayer(target: SeekTarget, seconds: number): void {
	target.currentTime = seconds;
}

// Минимальная поверхность нативного плеера, нужная для смены скорости.
export interface PlaybackRateTarget {
	playbackRate: number;
	pause(): void;
}

// iOS/AVPlayer может начать воспроизведение от установки playbackRate.
// Поэтому после смены скорости возвращаем паузу, если плеер был на паузе;
// иначе переключение скорости на паузе неожиданно запускало бы видео.
export function updatePlaybackRate(
	target: PlaybackRateTarget,
	rate: number,
	wasPlaying: boolean,
): void {
	target.playbackRate = rate;
	if (!wasPlaying) {
		target.pause();
	}
}

// Границы для accessibilityValue таймлайна: max — целая длительность,
// now не выходит за 0..max даже при мусорных/отрицательных значениях.
export function timelineBounds(
	position: number,
	duration: number,
): { max: number; now: number } {
	const max =
		Number.isFinite(duration) && duration > 0 ? Math.round(duration) : 0;
	const raw = Number.isFinite(position) ? Math.round(position) : 0;
	return { max, now: Math.min(Math.max(raw, 0), max) };
}

export function progressRatio(position: number, duration: number): number {
	if (!Number.isFinite(duration) || duration <= 0) {
		return 0;
	}
	if (!Number.isFinite(position) || position <= 0) {
		return 0;
	}
	return Math.min(1, position / duration);
}

// Дополнительная эвристика, а не триггер авто-ретрая: iOS/AVPlayer может не
// класть HTTP-статус в текст ошибки, поэтому useVideoSource делает preflight
// через общий apiFetch на первую же ошибку плеера. Здесь 401 распознаётся по
// тексту только для диагностики/тестов; \b401\b не цепляет 4010.
const UNAUTHORIZED_PATTERN = /\b401\b|unauthorized/i;

export function isUnauthorizedError(message: string): boolean {
	return UNAUTHORIZED_PATTERN.test(message);
}

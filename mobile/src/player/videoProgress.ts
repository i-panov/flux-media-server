import type { SaveProgressInput } from "@flux/shared";

// Позиция уходит на сервер не чаще раза в 5 секунд воспроизведения.
export const SAVE_INTERVAL_MS = 5_000;
// Ближе этого к началу считаем, что пользователь вернулся в 0 и прогресс
// нужно удалить, а не сохранить (паритет с web).
export const RESET_POSITION_SECONDS = 0.5;
// Допуск дрейфа при resume: источник/401-восстановление могли уже сдвинуть
// плеер, и это не должно считаться «пользователь начал смотреть».
export const RESUME_DRIFT_SECONDS = 1;

// 90% и выше — просмотр завершён (тот же порог, что в web и shared).
// Сравниваем 10*position >= 9*duration: дробное 0.9 даёт ложные промахи на
// ровно 90% для части длительностей.
export function isCompleted(position: number, duration: number): boolean {
	if (
		!Number.isFinite(position) ||
		!Number.isFinite(duration) ||
		duration <= 0
	) {
		return false;
	}
	return position * 10 >= duration * 9;
}

export interface ProgressSaveGate {
	position: number;
	duration: number;
	now: number;
	/** null — в этой сессии ещё ничего не отправляли. */
	lastSavedAt: number | null;
	/** -1 — в этой сессии ещё ничего не отправляли. */
	lastSavedPosition: number;
	/** pause/unmount/end игнорируют интервал, но не повтор той же позиции. */
	force?: boolean;
	/** После end обычные тики не сохраняют перезапуск с нуля. */
	ended?: boolean;
}

// Решение «пора ли отправлять PUT» вынесено из хука: так троттлинг, защита от
// дублей и завершение проверяются без нативного плеера.
export function shouldSaveProgress({
	position,
	duration,
	now,
	lastSavedAt,
	lastSavedPosition,
	force = false,
	ended = false,
}: ProgressSaveGate): boolean {
	if (
		!Number.isFinite(position) ||
		!Number.isFinite(duration) ||
		!Number.isFinite(now)
	) {
		return false;
	}
	const seconds = Math.floor(position);
	const total = Math.floor(duration);
	// Нулевая/неизвестная длительность — источник ещё не готов либо это
	// аудиопоток без метаданных: сохранять нечего.
	if (total <= 0 || seconds <= 0 || seconds > total) {
		return false;
	}
	// End уже сохранил финальную позицию: поздние тики после seek в 0 её бы
	// перезаписали.
	if (ended && !force) {
		return false;
	}
	// Повтор той же секунды бесполезен, даже по pause/unmount: это PUT-шторм.
	if (seconds === lastSavedPosition) {
		return false;
	}
	if (force) {
		return true;
	}
	// lastSavedAt=null — первое сохранение в сессии, ждать интервал не нужно.
	return lastSavedAt === null || now - lastSavedAt >= SAVE_INTERVAL_MS;
}

export interface ProgressDeleteGate {
	position: number;
	/** В этой сессии реально играло: до старта 0 удалять нечего. */
	playedOnce: boolean;
	/** Плеер уже уходил от начала: обычный старт с 0 не считается reset. */
	wasAwayFromStart: boolean;
	/** Автоматический seek в 0 после end не должен стирать completed. */
	ended?: boolean;
	/** DELETE уже отправлен, нового PUT не было. */
	alreadyDeleted?: boolean;
}

// Ручной возврат к началу после playback — это reset: серверную запись надо
// удалить, иначе переоткрытие вернёт на старое место. Ноль до старта и
// автоматический seek после end сюда не попадают.
export function shouldDeleteProgress({
	position,
	playedOnce,
	wasAwayFromStart,
	ended = false,
	alreadyDeleted = false,
}: ProgressDeleteGate): boolean {
	if (
		!playedOnce ||
		!wasAwayFromStart ||
		ended ||
		alreadyDeleted ||
		!Number.isFinite(position)
	) {
		return false;
	}
	return position >= 0 && position <= RESET_POSITION_SECONDS;
}

export interface StoredProgress {
	position: number;
	duration: number;
	completed: boolean;
}

export interface ResumeContext {
	/** Длительность загруженного источника; 0 — ещё неизвестна. */
	duration: number;
	/** Текущая позиция плеера: после 401 там уже может быть восстановлено. */
	currentPosition: number;
	/** Пользователь уже запускал playback. */
	hasStarted: boolean;
}

// null — resume не нужен (записи нет/404, просмотр завершён, пользователь уже
// начал, позиция уже восстановлена после 401 или некорректна). Иначе —
// секунда, на которую нужно один раз перемотать после loaded.
export function resumePosition(
	progress: StoredProgress | null,
	{ duration, currentPosition, hasStarted }: ResumeContext,
): number | null {
	if (progress === null || progress.completed || hasStarted) {
		return null;
	}
	const current = Number.isFinite(currentPosition)
		? Math.max(currentPosition, 0)
		: 0;
	if (current > RESUME_DRIFT_SECONDS) {
		return null;
	}
	const position = Number.isFinite(progress.position) ? progress.position : 0;
	if (position <= 0) {
		return null;
	}
	const total =
		Number.isFinite(duration) && duration > 0 ? duration : progress.duration;
	if (!Number.isFinite(total) || total <= 0) {
		return null;
	}
	const target = Math.min(position, total);
	if (target <= 0 || isCompleted(target, total)) {
		return null;
	}
	return target;
}

// Контракт PUT /progress/:mediaId: целые секунды, позиция не выходит за
// длительность, completed считается по тем же округлённым значениям.
export function buildProgressPayload(
	mediaId: number,
	position: number,
	duration: number,
): SaveProgressInput {
	const total = Number.isFinite(duration)
		? Math.max(Math.floor(duration), 0)
		: 0;
	const raw = Number.isFinite(position) ? Math.max(Math.floor(position), 0) : 0;
	const seconds = total > 0 ? Math.min(raw, total) : raw;
	return {
		mediaId,
		position: seconds,
		duration: total,
		completed: isCompleted(seconds, total),
	};
}

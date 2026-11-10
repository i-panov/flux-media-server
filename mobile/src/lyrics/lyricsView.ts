import {
	parseSyncedLyrics,
	type SyncedLyricLine,
	syncedLyricIndex,
} from "@flux/shared";

export type LyricsTab = "lyrics" | "translation";

const MEDIA_ID_PATTERN = /^\d+$/;

// Перевод из одних пробелов — это пустой перевод: вкладка не нужна.
export function hasTranslation(translation: string): boolean {
	return translation.trim() !== "";
}

export interface LyricsContentFields {
	lyrics_text: string;
	translation: string;
	sync_data: string;
}

// Запись без единого непробельного поля — это «текста нет», даже если
// бэкенд после очистки оставил строку в таблице.
export function hasLyricsContent(
	lyrics: LyricsContentFields | null | undefined,
): boolean {
	return (
		(lyrics?.lyrics_text ?? "").trim() !== "" ||
		(lyrics?.translation ?? "").trim() !== "" ||
		(lyrics?.sync_data ?? "").trim() !== ""
	);
}

// Стартовая вкладка: без текста (включая LRC-строки) показываем перевод,
// если он есть. Пользовательский выбор вкладки этот helper не отменяет.
export function defaultLyricsTab(
	hasText: boolean,
	translation: string,
): LyricsTab {
	return !hasText && hasTranslation(translation) ? "translation" : "lyrics";
}

export function hasLyricsText(lyricsText: string, syncData: string): boolean {
	return lyricsText.trim() !== "" || parseSyncedLyrics(syncData).length > 0;
}

// Активная вкладка не должна оставаться на скрытом переводе, например
// после очистки перевода в админском редакторе.
export function resolveLyricsTab(
	requested: LyricsTab,
	translation: string,
): LyricsTab {
	return requested === "translation" && !hasTranslation(translation)
		? "lyrics"
		: requested;
}

// Подсветка относится к позиции играющего трека. Для чужого трека
// currentTime — чужая шкала, поэтому индекс всегда -1.
export function highlightLineIndex(
	lines: SyncedLyricLine[],
	position: number,
	isCurrentTrack: boolean,
): number {
	return isCurrentTrack ? syncedLyricIndex(lines, position) : -1;
}

// Разбор LRC остаётся в shared; здесь только точка входа для экрана.
export function syncedLines(syncData: string): SyncedLyricLine[] {
	return parseSyncedLyrics(syncData);
}

// id из маршрута: строго цифры (без пробелов, знаков, экспоненты и hex).
// Мусор/deep link с /audio/0 не должен уходить в запросы.
export function parseMediaIdParam(
	value: string | readonly string[] | undefined,
): number | null {
	const raw = Array.isArray(value) ? value[0] : value;
	if (raw === undefined || !MEDIA_ID_PATTERN.test(raw)) {
		return null;
	}
	const id = Number(raw);
	return Number.isSafeInteger(id) && id > 0 ? id : null;
}

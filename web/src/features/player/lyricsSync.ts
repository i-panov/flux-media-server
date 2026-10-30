// Разбор LRC-синхронизации в записи (время в секундах, текст) —
// полное зеркало Flutter-парсера (lyrics_sync_parser.dart):
// доли секунд сохраняются полностью, строка с несколькими таймкодами
// порождает запись на каждый, текст — после последнего тега.
const LRC_TIMECODE_PATTERN = /\[(\d+):(\d+(?:\.\d+)?)\]/g;

export interface SyncedLyricLine {
	time: number;
	text: string;
}

export function parseSyncedLyrics(syncData: string): SyncedLyricLine[] {
	const result: SyncedLyricLine[] = [];
	for (const rawLine of syncData.split("\n")) {
		const line = rawLine.trim();
		if (line === "") {
			continue;
		}
		LRC_TIMECODE_PATTERN.lastIndex = 0;
		const matches = [...line.matchAll(LRC_TIMECODE_PATTERN)];
		if (matches.length === 0) {
			continue;
		}
		const last = matches[matches.length - 1];
		if (last === undefined || last.index === undefined) {
			continue;
		}
		const text = line.slice(last.index + last[0].length).trim();
		for (const match of matches) {
			const minutes = Number(match[1]);
			const seconds = Number(match[2]);
			if (!Number.isFinite(minutes) || !Number.isFinite(seconds)) {
				continue;
			}
			result.push({ time: minutes * 60 + seconds, text });
		}
	}
	// Теги в строке могут идти не по порядку — подсветка ищет последнюю
	// прошедшую, поэтому результат всегда отсортирован по времени.
	result.sort((a, b) => a.time - b.time);
	return result;
}

// Индекс текущей строки: последняя с временем не позже позиции.
// Пустой текст не подсвечиваем отдельно — он просто строка без слов.
export function syncedLyricIndex(
	lines: SyncedLyricLine[],
	position: number,
): number {
	let index = -1;
	for (let i = 0; i < lines.length; i += 1) {
		const line = lines[i];
		if (line !== undefined && line.time <= position) {
			index = i;
		}
	}
	return index;
}

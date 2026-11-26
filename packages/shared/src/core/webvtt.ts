// Минимальный парсер WebVTT для мобильного оверлея субтитров: expo-video
// не принимает внешние .vtt, поэтому cues разбираем сами.
export interface VttCue {
	start: number;
	end: number;
	text: string;
}

const TIMESTAMP = /^(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})$/;
const BOM = /^\uFEFF/;
const CRLF = /\r\n?/g;
const BLANK_LINE = /\n{2,}/;
const WHITESPACE = /\s+/;
const INLINE_TAGS = /<[^>]*>/g;
const ASS_OVERRIDES = /\{[^}]*\}/g;
const ENTITY = /&(amp|lt|gt|nbsp|lrm|rlm|quot|#\d+|#x[0-9a-f]+);/gi;
const NAMED_ENTITIES: Record<string, string> = {
	amp: "&",
	lt: "<",
	gt: ">",
	nbsp: " ",
	lrm: "",
	rlm: "",
	quot: '"',
};

function parseTimestamp(raw: string): number | null {
	const match = TIMESTAMP.exec(raw.trim());
	if (match === null) {
		return null;
	}
	const hours = match[1] === undefined ? 0 : Number(match[1]);
	const minutes = Number(match[2]);
	const seconds = Number(match[3]);
	const millis = Number((match[4] ?? "").padEnd(3, "0").slice(0, 3));
	return hours * 3600 + minutes * 60 + seconds + millis / 1000;
}

// Один проход: иначе &amp;lt; декодировался бы дважды.
function decodeEntities(text: string): string {
	return text.replace(ENTITY, (_match, name: string) => {
		const key = name.toLowerCase();
		const named = NAMED_ENTITIES[key];
		if (named !== undefined) {
			return named;
		}
		if (key.startsWith("#x")) {
			return String.fromCodePoint(Number.parseInt(key.slice(2), 16));
		}
		if (key.startsWith("#")) {
			return String.fromCodePoint(Number.parseInt(key.slice(1), 10));
		}
		return _match;
	});
}

// WebVTT/ASS-разметка: RN Text не парсит HTML, теги иначе видны буквально.
function stripMarkup(text: string): string {
	return text.replace(INLINE_TAGS, "").replace(ASS_OVERRIDES, "");
}

// Поддерживает BOM/CRLF, NOTE/STYLE/REGION-блоки, идентификаторы cue,
// настройки после таймкода и многострочный текст.
export function parseWebVtt(input: string): VttCue[] {
	const normalized = input.replace(BOM, "").replace(CRLF, "\n").trim();
	if (normalized === "") {
		return [];
	}
	const blocks = normalized.split(BLANK_LINE);
	const cues: VttCue[] = [];
	for (const block of blocks) {
		const lines = block.split("\n");
		const first = lines[0].trim();
		if (
			first === "WEBVTT" ||
			first.startsWith("WEBVTT ") ||
			first === "NOTE" ||
			first.startsWith("NOTE ") ||
			first === "STYLE" ||
			first.startsWith("STYLE ") ||
			first === "REGION" ||
			first.startsWith("REGION ")
		) {
			continue;
		}
		let timingIndex = 0;
		while (timingIndex < lines.length && !lines[timingIndex].includes("-->")) {
			timingIndex += 1;
		}
		if (timingIndex >= lines.length) {
			continue;
		}
		const [rawStart, rawRest] = lines[timingIndex].split("-->");
		if (rawRest === undefined) {
			continue;
		}
		const start = parseTimestamp(rawStart);
		// После таймкода могут идти настройки показа (align:start position:10%).
		const end = parseTimestamp(rawRest.trim().split(WHITESPACE)[0] ?? "");
		if (start === null || end === null || end <= start) {
			continue;
		}
		const text = stripMarkup(
			decodeEntities(
				lines
					.slice(timingIndex + 1)
					.join("\n")
					.trim(),
			),
		);
		if (text === "") {
			continue;
		}
		cues.push({ start, end, text });
	}
	return cues.sort((a, b) => a.start - b.start);
}

// Текст активной дорожки для позиции плеера; null — пауза между cue.
export function activeSubtitleText(
	cues: readonly VttCue[],
	position: number,
): string | null {
	let active: VttCue | null = null;
	for (const cue of cues) {
		if (cue.start > position) {
			break;
		}
		if (position < cue.end) {
			active = cue;
		}
	}
	return active?.text ?? null;
}

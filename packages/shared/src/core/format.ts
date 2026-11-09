// Чистые форматтеры без зависимостей: одно место для веба и mobile.
export function formatDuration(totalSeconds: number): string {
	const total = Math.max(0, Math.floor(totalSeconds));
	const hours = Math.floor(total / 3600);
	const minutes = Math.floor((total % 3600) / 60);
	const seconds = total % 60;
	const minutePart =
		hours > 0 ? String(minutes).padStart(2, "0") : String(minutes);
	return `${hours > 0 ? `${hours}:` : ""}${minutePart}:${String(seconds).padStart(2, "0")}`;
}

// Размер файла для списка загрузок. Один десятичный знак у KB+.
export function formatFileSize(bytes: number): string {
	const size = Math.max(0, bytes);
	if (size < 1024) {
		return `${size} B`;
	}
	if (size < 1024 * 1024) {
		return `${(size / 1024).toFixed(1)} KB`;
	}
	if (size < 1024 * 1024 * 1024) {
		return `${(size / (1024 * 1024)).toFixed(1)} MB`;
	}
	return `${(size / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

const SUB_LANG_SUFFIX_PATTERN = /\d+$/;
const BCP47_TAG_PATTERN = /^[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,8})*$/;

// Бэкенд дедуплицирует языки цифровым суффиксом (rus2, es-4192), а srclang —
// BCP47-тег. Суффикс срезаем, только если остаток похож на тег: числовые
// подтеги регионов и вариантов (es-419, en-001, de-1996) трогать нельзя,
// иначе получится невалидный тег вроде "es-".
export function splitSubLang(lang: string): { base: string; label: string } {
	const base = lang.replace(SUB_LANG_SUFFIX_PATTERN, "");
	if (base === "" || base === lang || !BCP47_TAG_PATTERN.test(base)) {
		return { base: lang, label: lang };
	}
	return { base, label: `${base} (${lang.slice(base.length)})` };
}

const FILENAME_TITLE_YEAR_PATTERN = /^(.+)\.(\d{4})\.[^.]+$/;
const FILENAME_TITLE_PAREN_YEAR_PATTERN = /^(.+)\s*\((\d{4})\)\.[^.]+$/;
const FILENAME_TITLE_EPISODE_PATTERN = /^(.+)\.S(\d{2})E(\d{2})\..+$/;

// Название и год из имени файла — зеркало Flutter FilenameParser:
// Title.Year.ext, Title (Year).ext, Title.S01E05.ext, иначе имя без
// расширения с точками вместо пробелов.
export function parseFilename(filename: string): {
	title: string;
	year: number | null;
} {
	const dot = FILENAME_TITLE_YEAR_PATTERN.exec(filename);
	if (dot?.[1] !== undefined && dot[2] !== undefined) {
		return {
			title: dot[1].replaceAll(".", " "),
			year: Number(dot[2]),
		};
	}
	const paren = FILENAME_TITLE_PAREN_YEAR_PATTERN.exec(filename);
	if (paren?.[1] !== undefined && paren[2] !== undefined) {
		return {
			title: paren[1].trim().replaceAll(".", " "),
			year: Number(paren[2]),
		};
	}
	const episode = FILENAME_TITLE_EPISODE_PATTERN.exec(filename);
	if (episode?.[1] !== undefined) {
		return { title: episode[1].replaceAll(".", " "), year: null };
	}
	const parts = filename.split(".");
	if (parts.length > 1) {
		parts.pop();
	}
	return { title: parts.join(" "), year: null };
}

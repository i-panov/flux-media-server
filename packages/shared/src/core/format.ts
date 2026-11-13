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
	if (!Number.isFinite(bytes) || bytes <= 0) {
		return "0 B";
	}
	const units = ["B", "KB", "MB", "GB", "TB"];
	let value = bytes;
	let unit = 0;
	while (value >= 1024 && unit < units.length - 1) {
		value /= 1024;
		unit += 1;
	}
	const rounded =
		value >= 10 || Number.isInteger(value)
			? Math.round(value)
			: Math.round(value * 10) / 10;
	return `${rounded} ${units[unit]}`;
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

const FILENAME_EPISODE_PATTERN =
	/^(.*?)[. _-](?:S(\d{1,2})E(\d{1,2})|(\d{1,2})x(\d{1,2}))(?:[. _-].*)?$/i;
const FILENAME_YEAR_PATTERN = /(?:^|[. _(-])((?:18|19|20)\d{2})(?=$|[. _)-])/g;

// Название и год из имени файла. Год — последний валидный 4-значный
// сегмент (18xx..20xx), а не «1080»/«2160»; сериалы S1E1 и 1x01
// распознаются до года, чтобы «Show.S01E05.2020» не стал годом шоу.
export function parseFilename(filename: string): {
	title: string;
	year: number | null;
} {
	const stem = filename.replace(/\.[^.]+$/, "");
	const episode = FILENAME_EPISODE_PATTERN.exec(stem);
	if (episode?.[1] !== undefined) {
		return { title: episode[1].trim().replace(/[._]+/g, " "), year: null };
	}
	let year: number | null = null;
	let yearIndex = -1;
	for (const match of stem.matchAll(FILENAME_YEAR_PATTERN)) {
		const value = Number(match[1]);
		const now = new Date().getFullYear();
		if (value >= 1888 && value <= now + 2) {
			year = value;
			yearIndex = match.index;
		}
	}
	if (year !== null && yearIndex >= 0) {
		return {
			title: stem
				.slice(0, yearIndex)
				.replace(/[. _-]+$/g, "")
				.replace(/[._]+/g, " ")
				.trim(),
			year,
		};
	}
	return { title: stem.replace(/[._]+/g, " ").trim(), year: null };
}

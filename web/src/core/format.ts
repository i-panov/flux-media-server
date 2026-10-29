// Чистые форматтеры без зависимостей: одно место для веба и будущего
// мобильного приложения.
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

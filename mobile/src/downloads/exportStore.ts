import type { MediaType } from "@flux/shared";
import { type DownloadEntry, downloadExtension } from "./downloadStore";

// Экспорт скачанного файла через системный share sheet. Чистые правила
// (MIME, безопасное имя, опции sharing) вынесены из нативного модуля,
// чтобы проверяться в Node без expo-sharing/React Native.

export type DownloadExportFailure = "unavailable" | "missing" | "error";

type ExportableEntry = Pick<
	DownloadEntry,
	"mediaId" | "title" | "type" | "filename"
>;

const IMAGE_JPEG = "image/jpeg";
const EXPORT_STAGING_DIRECTORY = "flux-export";
// Имя в share sheet должно оставаться читаемым, но не превращаться в
// простыню: лимит считаем по code points, чтобы не разрезать emoji.
const MAX_EXPORT_BASE_LENGTH = 80;
const UNSAFE_FILENAME_CHARS = /[\\/:*?"<>|#%]/g;
const CONTROL_CHARS = /\p{Cc}/gu;
const WHITESPACE = /\s+/g;
const EDGE_DOTS_OR_SPACES = /^[.\s]+|[.\s]+$/g;

// MIME нужен Android-интенту: по нему система выбирает приложения и
// показывает корректное имя. iOS определяет тип по расширению файла.
const MIME_BY_EXTENSION: Readonly<Record<string, string>> = {
	mp4: "video/mp4",
	m4v: "video/mp4",
	mkv: "video/x-matroska",
	avi: "video/x-msvideo",
	mov: "video/quicktime",
	wmv: "video/x-ms-wmv",
	webm: "video/webm",
	flv: "video/x-flv",
	ts: "video/mp2t",
	mp3: "audio/mpeg",
	flac: "audio/flac",
	ogg: "audio/ogg",
	oga: "audio/ogg",
	m4a: "audio/mp4",
	m4b: "audio/mp4",
	aac: "audio/aac",
	wav: "audio/wav",
	opus: "audio/ogg",
	wma: "audio/x-ms-wma",
	jpg: IMAGE_JPEG,
	jpeg: IMAGE_JPEG,
	png: "image/png",
	gif: "image/gif",
	webp: "image/webp",
	bmp: "image/bmp",
};

const FALLBACK_MIME: Readonly<Record<MediaType, string>> = {
	video: "video/mp4",
	audio: "audio/mpeg",
	image: IMAGE_JPEG,
};

// Пользовательский title может содержать разделители пути, запрещённые
// символы и точки по краям. Заменяем их пробелами, схлопываем повторы и
// обрезаем; пустой результат позже заменяется на media-<id>. Разделители
// путей вычищаются, поэтому выйти из staging-каталога именем нельзя.
function exportTitleBase(title: string): string {
	const cleaned = title
		.replace(UNSAFE_FILENAME_CHARS, " ")
		.replace(CONTROL_CHARS, " ")
		.replace(WHITESPACE, " ")
		.replace(EDGE_DOTS_OR_SPACES, "");
	const truncated = [...cleaned].slice(0, MAX_EXPORT_BASE_LENGTH).join("");
	return truncated.replace(EDGE_DOTS_OR_SPACES, "");
}

// Пользователь видит в share sheet человеческое имя вместо media-7.mp4.
// Расширение берём из сохранённого файла (downloadExtension уже откатывается
// к типу media), чтобы получатель открыл контейнер правильным приложением.
export function exportFileName(entry: ExportableEntry): string {
	const base = exportTitleBase(entry.title) || `media-${entry.mediaId}`;
	return `${base}${downloadExtension(entry)}`;
}

// Staging — отдельный каталог в cacheDirectory, а не downloads/: гидратация
// индекса удаляет из downloads/ всё, чего нет в записях, и могла бы снести
// файл прямо во время share sheet. CacheDirectory чистит и сама ОС.
export function exportStagingDirectory(
	cacheDirectory: string | null,
): string | null {
	if (cacheDirectory === null || cacheDirectory === "") {
		return null;
	}
	const base = cacheDirectory.endsWith("/")
		? cacheDirectory
		: `${cacheDirectory}/`;
	return `${base}${EXPORT_STAGING_DIRECTORY}/`;
}

export function exportStagingPath(
	cacheDirectory: string | null,
	entry: ExportableEntry,
): string | null {
	const directory = exportStagingDirectory(cacheDirectory);
	return directory === null ? null : `${directory}${exportFileName(entry)}`;
}

// Имя файла в индексе уже проверено downloadStore: безопасные символы и
// известное расширение. Неизвестный/отсутствующий extension откатываем к
// типу media, чтобы Android всё равно получил валидный MIME.
export function downloadMimeType(entry: ExportableEntry): string {
	const dot = entry.filename.lastIndexOf(".");
	const extension =
		dot > 0 && dot < entry.filename.length - 1
			? entry.filename.slice(dot + 1).toLowerCase()
			: "";
	return MIME_BY_EXTENSION[extension] ?? FALLBACK_MIME[entry.type];
}

export interface ExportShareOptions {
	readonly mimeType?: string;
	readonly dialogTitle?: string;
}

// mimeType передаём только Android: по документации expo-sharing на iOS он
// может дописать второе расширение к уже существующему (media-7.mp4.mp4).
// iOS и так определяет тип файла по расширению.
export function exportShareOptions(
	entry: ExportableEntry,
	dialogTitle: string,
	platform: string,
): ExportShareOptions {
	if (platform !== "android") {
		return {};
	}
	return { mimeType: downloadMimeType(entry), dialogTitle };
}

import type { Media, MediaType } from "@flux/shared";

// Офлайн-скачивания: чистые правила индекса, имён файлов, квоты и
// HTTP-ответов. Модуль намеренно не импортирует React Native/FileSystem/
// AsyncStorage, чтобы проверяться в Node. Нативные операции — в runner.

export const DOWNLOAD_INDEX_KEY = "flux.downloads.v1";
export const DOWNLOAD_INDEX_VERSION = 1;
// Кеш на устройстве ограничен 2 ГиБ. При переполнении вытесняются самые
// старые завершённые файлы; активные загрузки и свежий файл не трогаем.
export const DOWNLOAD_QUOTA_BYTES = 2 * 1024 * 1024 * 1024;
export const DOWNLOAD_DIRECTORY_NAME = "downloads";
// Час на один файл: зависший сокет не должен оставлять «Скачивание» навсегда.
export const DOWNLOAD_TIMEOUT_MS = 60 * 60 * 1000;

export type DownloadFailure =
	| "network"
	| "status"
	| "size"
	| "storage"
	| "timeout";

export interface DownloadEntry {
	readonly mediaId: number;
	readonly title: string;
	readonly type: MediaType;
	/** Только имя файла: iOS может сменить UUID контейнера между запусками. */
	readonly filename: string;
	readonly size: number;
	readonly updatedAt: number;
}

export interface DownloadIndex {
	/** baseUrl сервера, которому принадлежит индекс; null — legacy-запись. */
	readonly server: string | null;
	readonly entries: DownloadEntry[];
}

// Расширение берём из исходного имени файла: backend может отдать
// извлечённый .m4a или .webm, и player лучше определяет контейнер по нему.
// Fallback — безопасный тип media. Расширение допускает только буквы/цифры,
// поэтому имя вида "../../evil.mp4" не может выйти за каталог.
const FALLBACK_EXTENSION: Record<MediaType, string> = {
	video: ".mp4",
	audio: ".mp3",
	image: ".jpg",
};

const SAFE_EXTENSION = /^[a-z0-9]{1,12}$/;
const PATH_SEPARATORS = /[\\/]/;
const QUERY_FRAGMENT = /[?#]/;
// Только контейнеры, которые умеют открывать expo-video/expo-audio. Чужое
// расширение (например .exe из имени) не должно попадать в локальный путь.
const MEDIA_EXTENSIONS: ReadonlySet<string> = new Set([
	"mp4",
	"m4v",
	"mkv",
	"avi",
	"mov",
	"wmv",
	"webm",
	"flv",
	"ts",
	"mp3",
	"flac",
	"ogg",
	"oga",
	"m4a",
	"m4b",
	"aac",
	"wav",
	"opus",
	"wma",
	"jpg",
	"jpeg",
	"png",
	"gif",
	"webp",
	"bmp",
]);

// Имя файла хранится в индексе отдельно от каталога. Разрешены только
// безопасные символы; ".." запрещён, чтобы старый/битый индекс не вывел
// удаление или чтение за пределы downloads/.
const SAFE_FILENAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$/;

export function isSafeDownloadFilename(value: string): boolean {
	return SAFE_FILENAME.test(value) && !value.includes("..");
}

const MEDIA_TYPES: ReadonlySet<string> = new Set<MediaType>([
	"video",
	"audio",
	"image",
]);

// Media.type в shared — строка (бэкенд может отдать неизвестное значение).
// Для имени файла и индекса сводим её к известному MediaType, иначе
// запись не пройдёт валидацию при следующем запуске.
export function normalizeMediaType(type: string): MediaType {
	if (type === "audio" || type === "image" || type === "video") {
		return type;
	}
	return "video";
}

// Последний сегмент имени без query/fragment, затем расширение после
// последней точки. Скрытые файлы (".mp4") и имена без расширения дают
// fallback: точка в начале не считается расширением.
export function downloadExtension(
	media: Pick<Media, "type" | "filename">,
): string {
	const base = media.filename.split(PATH_SEPARATORS).pop() ?? "";
	const clean = base.split(QUERY_FRAGMENT)[0] ?? "";
	const dot = clean.lastIndexOf(".");
	if (dot > 0 && dot < clean.length - 1) {
		const extension = clean.slice(dot + 1).toLowerCase();
		if (SAFE_EXTENSION.test(extension) && MEDIA_EXTENSIONS.has(extension)) {
			return `.${extension}`;
		}
	}
	return FALLBACK_EXTENSION[normalizeMediaType(media.type)];
}

// Детерминированное имя без пользовательского title: один mediaId — один
// файл, переименование медиа не оставляет осиротевших копий. id числовой,
// а расширение проходит SAFE_EXTENSION, поэтому path traversal невозможен.
export function downloadFileName(
	media: Pick<Media, "id" | "type" | "filename">,
): string {
	return `media-${media.id}${downloadExtension(media)}`;
}

// documentDirectory может быть null (web/неинициализированный FileSystem).
export function downloadDirectory(
	documentDirectory: string | null,
): string | null {
	if (documentDirectory === null || documentDirectory === "") {
		return null;
	}
	const base = documentDirectory.endsWith("/")
		? documentDirectory
		: `${documentDirectory}/`;
	return `${base}${DOWNLOAD_DIRECTORY_NAME}/`;
}

// Путь каждый раз собирается из актуального documentDirectory и имени из
// индекса: абсолютный путь в AsyncStorage ломается после переезда контейнера.
export function downloadFilePath(
	documentDirectory: string | null,
	filename: string,
): string | null {
	if (!isSafeDownloadFilename(filename)) {
		return null;
	}
	const directory = downloadDirectory(documentDirectory);
	return directory === null ? null : `${directory}${filename}`;
}

export function partPathFor(path: string): string {
	return `${path}.part`;
}

// Заголовки в ответе приходят в разном регистре: Content-Length,
// content-length. Значение 0 валидно, пустое/нечисловое — отсутствует.
export function headerValue(
	headers: Readonly<Record<string, string>>,
	name: string,
): string | null {
	const target = name.toLowerCase();
	for (const [key, value] of Object.entries(headers)) {
		if (key.toLowerCase() !== target) {
			continue;
		}
		const trimmed = value.trim();
		return trimmed === "" ? null : trimmed;
	}
	return null;
}

export function contentLength(
	headers: Readonly<Record<string, string>>,
): number | null {
	const raw = headerValue(headers, "content-length");
	if (raw === null) {
		return null;
	}
	const value = Number(raw);
	return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

// Свежая загрузка начинается с 0, поэтому ожидаем 200. 206 допустим:
// некоторые прокси/CDN отвечают Range-фрагментом даже без Range-запроса.
export function isDownloadStatusOk(status: number): boolean {
	return status === 200 || status === 206;
}

export interface ContentRange {
	readonly start: number;
	readonly end: number;
	readonly total: number | null;
}

const CONTENT_RANGE_PATTERN = /^bytes\s+(\d+)-(\d+)\/(\d+|\*)$/i;

export function parseContentRange(
	headers: Readonly<Record<string, string>>,
): ContentRange | null {
	const raw = headerValue(headers, "content-range");
	if (raw === null) {
		return null;
	}
	const match = CONTENT_RANGE_PATTERN.exec(raw);
	if (match === null) {
		return null;
	}
	const start = Number(match[1]);
	const end = Number(match[2]);
	const totalRaw = match[3];
	const total =
		totalRaw === "*" || totalRaw === undefined ? null : Number(totalRaw);
	if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end)) {
		return null;
	}
	if (total !== null && !Number.isSafeInteger(total)) {
		return null;
	}
	return { start, end, total };
}

// 206 нельзя считать целым файлом только по Content-Length: это длина
// фрагмента. Требуем Content-Range с началом 0 и полным total.
export function isCompleteDownload(
	status: number,
	headers: Readonly<Record<string, string>>,
	actualSize: number,
): boolean {
	if (status === 200) {
		return true;
	}
	if (status !== 206) {
		return false;
	}
	const range = parseContentRange(headers);
	if (range === null || range.start !== 0 || range.total === null) {
		return false;
	}
	return range.end === range.total - 1 && actualSize === range.total;
}

export type DownloadSizeCheck = "ok" | "unknown" | "mismatch";

// Content-Length может отсутствовать (chunked). Тогда размер принимаем как
// есть: доверять нулю/file.size без проверки нельзя, но и блокировать
// скачивание из-за отсутствия заголовка — нельзя.
export function checkDownloadedSize(
	actual: number,
	expected: number | null,
): DownloadSizeCheck {
	if (!Number.isSafeInteger(actual) || actual < 0) {
		return "mismatch";
	}
	if (expected === null) {
		return "unknown";
	}
	return actual === expected ? "ok" : "mismatch";
}

// -1/0 в totalBytesExpectedToWrite означает, что сервер не прислал
// Content-Length: UI получает null и показывает спиннер, а не 0%.
export function downloadProgressRatio(
	written: number,
	expected: number,
): number | null {
	if (!Number.isFinite(expected) || expected <= 0) {
		return null;
	}
	if (!Number.isFinite(written) || written < 0) {
		return 0;
	}
	return Math.min(Math.max(written / expected, 0), 1);
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function filenameFromLegacyPath(path: string): string | null {
	const base = path.split(PATH_SEPARATORS).pop() ?? "";
	const clean = base.split(QUERY_FRAGMENT)[0] ?? "";
	return isSafeDownloadFilename(clean) ? clean : null;
}

function parseEntry(value: unknown): DownloadEntry | null {
	if (!isRecord(value)) {
		return null;
	}
	const mediaId = value.mediaId;
	const title = value.title;
	const type = value.type;
	const filename = value.filename;
	const legacyPath = value.path;
	const size = value.size;
	const updatedAt = value.updatedAt;
	if (
		typeof mediaId !== "number" ||
		!Number.isSafeInteger(mediaId) ||
		mediaId <= 0 ||
		typeof title !== "string" ||
		typeof type !== "string" ||
		!MEDIA_TYPES.has(type) ||
		typeof size !== "number" ||
		!Number.isSafeInteger(size) ||
		size < 0 ||
		typeof updatedAt !== "number" ||
		!Number.isFinite(updatedAt) ||
		updatedAt <= 0
	) {
		return null;
	}
	let safeFilename: string | null = null;
	if (typeof filename === "string" && isSafeDownloadFilename(filename)) {
		safeFilename = filename;
	} else if (typeof legacyPath === "string") {
		// Индекс b3c564d хранил абсолютный path. Мигрируем в имя файла,
		// чтобы переезд iOS-контейнера не ломал существующие скачивания.
		safeFilename = filenameFromLegacyPath(legacyPath);
	}
	if (safeFilename === null) {
		return null;
	}
	return {
		mediaId,
		title,
		type: type as MediaType,
		filename: safeFilename,
		size,
		updatedAt,
	};
}

// Битый JSON, чужая версия и невалидные записи не должны ронять экран:
// возвращаем только то, что можно показать. Дубликаты по mediaId
// схлопываются в последнюю запись.
export function parseDownloadIndex(
	raw: string | null | undefined,
): DownloadIndex {
	const empty: DownloadIndex = { server: null, entries: [] };
	if (raw === null || raw === undefined || raw === "") {
		return empty;
	}
	let data: unknown;
	try {
		data = JSON.parse(raw) as unknown;
	} catch {
		return empty;
	}
	if (!isRecord(data) || data.version !== DOWNLOAD_INDEX_VERSION) {
		return empty;
	}
	if (!Array.isArray(data.items)) {
		return empty;
	}
	const server =
		typeof data.server === "string" && data.server.trim() !== ""
			? data.server
			: null;
	const byId = new Map<number, DownloadEntry>();
	for (const rawEntry of data.items) {
		const entry = parseEntry(rawEntry);
		if (entry !== null) {
			byId.set(entry.mediaId, entry);
		}
	}
	const entries = [...byId.values()].sort((left, right) => {
		return right.updatedAt - left.updatedAt || right.mediaId - left.mediaId;
	});
	return { server, entries };
}

export function serializeDownloadIndex(
	entries: readonly DownloadEntry[],
	server: string | null,
): string {
	return JSON.stringify({
		version: DOWNLOAD_INDEX_VERSION,
		server,
		items: entries,
	});
}

// Legacy-индекс без server нельзя проверить; принимаем его один раз и
// перезаписываем текущим сервером при следующем persist. Все последующие
// смены сервера индекс уже различает.
export function indexMatchesServer(
	indexServer: string | null,
	currentServer: string,
): boolean {
	return indexServer === null || indexServer === currentServer;
}

export function upsertDownloadEntry(
	entries: readonly DownloadEntry[],
	entry: DownloadEntry,
): DownloadEntry[] {
	return [entry, ...entries.filter((item) => item.mediaId !== entry.mediaId)];
}

export function removeDownloadEntry(
	entries: readonly DownloadEntry[],
	mediaId: number,
): DownloadEntry[] {
	return entries.filter((entry) => entry.mediaId !== mediaId);
}

export function findDownloadEntry(
	entries: readonly DownloadEntry[],
	mediaId: number,
): DownloadEntry | null {
	return entries.find((entry) => entry.mediaId === mediaId) ?? null;
}

// Резолвер по mediaId, а не по текущему current: при смене трека плеер
// должен получить путь именно нового media, не унаследовав старый.
export function resolveDownloadedPath(
	entries: readonly DownloadEntry[],
	hydrated: boolean,
	mediaId: number,
	documentDirectory: string | null,
): string | null {
	if (!hydrated) {
		return null;
	}
	const entry = findDownloadEntry(entries, mediaId);
	return entry === null
		? null
		: downloadFilePath(documentDirectory, entry.filename);
}

export interface DownloadQuotaOptions {
	readonly quotaBytes?: number;
	/** Сейчас скачиваются: вытеснять нельзя, иначе оборвём загрузку. */
	readonly activeIds?: ReadonlySet<number>;
	/** Только что завершённый файл: сохраняем даже при переполнении. */
	readonly protectedIds?: ReadonlySet<number>;
}

export interface DownloadQuotaResult {
	readonly kept: DownloadEntry[];
	readonly evicted: DownloadEntry[];
	readonly totalBytes: number;
}

function safeSize(entry: DownloadEntry): number {
	return Number.isFinite(entry.size) && entry.size > 0 ? entry.size : 0;
}

// Вытеснение по LRU: удаляем самые старые завершённые файлы, пока сумма
// не влезет в квоту. Порядок оставшихся не меняем, чтобы список не
// перескакивал. Если все файлы защищены, квота может остаться превышенной:
// оборвать активную загрузку ради цифры хуже, чем временно выйти за лимит.
export function evictDownloads(
	entries: readonly DownloadEntry[],
	options: DownloadQuotaOptions = {},
): DownloadQuotaResult {
	const quota =
		options.quotaBytes !== undefined &&
		Number.isSafeInteger(options.quotaBytes) &&
		options.quotaBytes >= 0
			? options.quotaBytes
			: DOWNLOAD_QUOTA_BYTES;
	const activeIds = options.activeIds ?? new Set<number>();
	const protectedIds = options.protectedIds ?? new Set<number>();
	const total = entries.reduce((sum, entry) => sum + safeSize(entry), 0);
	let remaining = total;
	const evictedIds = new Set<number>();
	// updatedAt одинаков у быстрых загрузок; mediaId даёт стабильный порядок.
	const candidates = [...entries].sort((left, right) => {
		return left.updatedAt - right.updatedAt || left.mediaId - right.mediaId;
	});
	for (const entry of candidates) {
		if (remaining <= quota) {
			break;
		}
		if (activeIds.has(entry.mediaId) || protectedIds.has(entry.mediaId)) {
			continue;
		}
		evictedIds.add(entry.mediaId);
		remaining -= safeSize(entry);
	}
	return {
		kept: entries.filter((entry) => !evictedIds.has(entry.mediaId)),
		evicted: entries.filter((entry) => evictedIds.has(entry.mediaId)),
		totalBytes: entries.reduce((sum, entry) => {
			return evictedIds.has(entry.mediaId) ? sum : sum + safeSize(entry);
		}, 0),
	};
}

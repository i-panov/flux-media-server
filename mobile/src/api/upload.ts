import {
	ApiError,
	apiFetch,
	getApiConfig,
	type Media,
	type MediaType,
	mediaSchema,
} from "@flux/shared";

// Загрузка файла в mobile идёт мимо apiFetch: fetch в React Native не умеет
// отдавать прогресс отправки, поэтому тело шлётся через XMLHttpRequest.
// Всё остальное (job status/cancel) остаётся на apiFetch — включая refresh
// токена на 401. Для XHR 401 обрабатывается одной предварительной проверкой
// через apiFetch и повтором запроса с новыми заголовками.

export const UPLOAD_POLL_INTERVAL_MS = 900;

// Таймаут одного XHR-POST: 30 минут. Backend буферизует тело целиком в RAM,
// поэтому таймаут не должен рубить большие файлы, но зависший сокет надо
// завершать понятной ошибкой, а не ждать вечно.
export const UPLOAD_TIMEOUT_MS = 30 * 60 * 1000;

// server.max_upload_size в backend/configs (default 2GB). Mobile не читает
// конфиг сервера, поэтому pre-check использует дефолтный лимит: файлы
// больше него отсекаются до POST. Фактическую проверку всё равно делает
// backend, поэтому неизвестный/нулевой size не блокируем.
export const MAX_UPLOAD_BYTES = 2 * 1024 * 1024 * 1024;

export type UploadJobKind = "upload" | "transcode";

export interface UploadJobRef {
	readonly id: number;
	readonly kind: UploadJobKind;
}

export interface UploadFile {
	readonly uri: string;
	readonly name: string;
	readonly type: string;
}

export interface UploadSource extends UploadFile {
	readonly mediaType: MediaType;
}

export interface UploadDuplicate {
	readonly id: number;
	readonly title: string;
}

export interface UploadJob {
	readonly id: number;
	readonly status: string;
	readonly error: string | null;
	readonly duplicate: UploadDuplicate | null;
	readonly media: Media | null;
	readonly progress: number | null;
	readonly speed: number | null;
	readonly etaSeconds: number | null;
}

const JPEG_MIME = "image/jpeg";

const MEDIA_TYPE_BY_EXTENSION: Record<string, MediaType> = {
	// video
	mp4: "video",
	m4v: "video",
	mkv: "video",
	avi: "video",
	mov: "video",
	wmv: "video",
	webm: "video",
	flv: "video",
	ts: "video",
	// audio
	mp3: "audio",
	flac: "audio",
	ogg: "audio",
	oga: "audio",
	m4a: "audio",
	aac: "audio",
	wav: "audio",
	opus: "audio",
	wma: "audio",
	// image
	jpg: "image",
	jpeg: "image",
	png: "image",
	gif: "image",
	webp: "image",
	bmp: "image",
};

const MIME_BY_EXTENSION: Record<string, string> = {
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
	aac: "audio/aac",
	wav: "audio/wav",
	opus: "audio/opus",
	wma: "audio/x-ms-wma",
	jpg: JPEG_MIME,
	jpeg: JPEG_MIME,
	png: "image/png",
	gif: "image/gif",
	webp: "image/webp",
	bmp: "image/bmp",
};

const DEFAULT_MIME: Record<MediaType, string> = {
	video: "video/mp4",
	audio: "audio/mpeg",
	image: JPEG_MIME,
};

const SUPPORTED_EXTENSIONS = new Set(Object.keys(MEDIA_TYPE_BY_EXTENSION));
const URI_QUERY_SPLIT = /[?#]/;

const DEFAULT_EXTENSION: Record<MediaType, string> = {
	video: ".mp4",
	audio: ".mp3",
	image: ".jpg",
};

// Последний сегмент URI без query/fragment: picker может отдать
// content:// URI с параметрами, а имя файла из него — уже чистым.
export function fileNameFromUri(uri: string): string {
	const clean = uri.split(URI_QUERY_SPLIT)[0] ?? "";
	return clean.slice(clean.lastIndexOf("/") + 1);
}

// Расширение без точки в нижнем регистре. Имя файла не трогаем: символы
// # и ? в имени пользователя — часть имени, а не query/fragment; URI
// очищается отдельно в fileNameFromUri.
export function fileExtension(filename: string): string {
	const base = filename.slice(filename.lastIndexOf("/") + 1);
	const dot = base.lastIndexOf(".");
	if (dot <= 0 || dot === base.length - 1) {
		return "";
	}
	return base.slice(dot + 1).toLowerCase();
}

// Тип медиа: сначала MIME от picker (он точнее), затем расширение.
// Неизвестное расширение/битый MIME — null: такой файл не отправляем,
// backend всё равно отвергнет его по расширению.
export function inferMediaType(
	mimeType: string | null | undefined,
	filename?: string,
): MediaType | null {
	const mime = mimeType?.trim().toLowerCase() ?? "";
	if (mime.startsWith("video/")) {
		return "video";
	}
	if (mime.startsWith("audio/")) {
		return "audio";
	}
	if (mime.startsWith("image/")) {
		return "image";
	}
	const extension = filename === undefined ? "" : fileExtension(filename);
	return MEDIA_TYPE_BY_EXTENSION[extension] ?? null;
}

// MIME для multipart-поля file: picker иногда отдаёт
// application/octet-stream, тогда тип восстанавливается по расширению.
export function uploadMimeType(
	mediaType: MediaType,
	filename: string,
	mimeType?: string | null,
): string {
	const provided = mimeType?.trim() ?? "";
	if (provided.toLowerCase().startsWith(`${mediaType}/`)) {
		return provided;
	}
	const mapped = MIME_BY_EXTENSION[fileExtension(filename)];
	if (mapped?.startsWith(`${mediaType}/`)) {
		return mapped;
	}
	return DEFAULT_MIME[mediaType];
}

// Picker возвращает uri/name/mimeType; здесь же имя получает расширение,
// если система его не отдала, — иначе backend не определит тип и отклонит.
export function createUploadSource(input: {
	uri: string;
	name?: string | null;
	mimeType?: string | null;
}): UploadSource | null {
	const uri = input.uri.trim();
	if (uri === "") {
		return null;
	}
	const fallbackName = fileNameFromUri(uri);
	let name = (input.name ?? "").trim() || fallbackName;
	const mediaType = inferMediaType(input.mimeType, name);
	if (mediaType === null) {
		return null;
	}
	const extension = fileExtension(name);
	// Picker с MIME-фильтром может отдать контейнер, который backend не
	// принимает (например, .heic): лучше пропустить его сразу, чем ждать 400.
	if (extension !== "" && !SUPPORTED_EXTENSIONS.has(extension)) {
		return null;
	}
	if (extension === "") {
		name = `${name}${DEFAULT_EXTENSION[mediaType]}`;
	}
	return {
		uri,
		name,
		type: uploadMimeType(mediaType, name, input.mimeType),
		mediaType,
	};
}

export function isFileTooLarge(size: number | null | undefined): boolean {
	return (
		typeof size === "number" && Number.isFinite(size) && size > MAX_UPLOAD_BYTES
	);
}

// Единицы латинские: подпись одинаково читается в ru/en и не требует
// отдельного словаря для каждого размера.
export { formatFileSize } from "@flux/shared";

export function clampPercent(value: number): number {
	if (!Number.isFinite(value)) {
		return 0;
	}
	return Math.min(100, Math.max(0, Math.round(value)));
}

// Доля отправленного тела в процентах. null — размер тела неизвестен
// (chunked/сжатый запрос): прогресс-бар должен остаться индетерминированным.
export function progressPercent(loaded: number, total: number): number | null {
	if (!Number.isFinite(loaded) || !Number.isFinite(total) || total <= 0) {
		return null;
	}
	return clampPercent((loaded / total) * 100);
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function positiveInteger(value: unknown): number | null {
	if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
		return null;
	}
	return value;
}

export function parseEnqueueResponse(
	body: unknown,
	mediaType: MediaType,
): UploadJobRef {
	if (!isRecord(body)) {
		throw new ApiError(202, "Invalid upload response", body);
	}
	const id = positiveInteger(body.job_id);
	if (id === null) {
		throw new ApiError(202, "Invalid upload response", body);
	}
	const rawKind = body.job_type;
	const kind: UploadJobKind =
		rawKind === "transcode" || rawKind === "upload"
			? rawKind
			: mediaType === "video"
				? "transcode"
				: "upload";
	return { id, kind };
}

function nullableNumber(value: unknown): number | null {
	return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function parseDuplicate(value: unknown): UploadDuplicate | null {
	if (!isRecord(value)) {
		return null;
	}
	const id = positiveInteger(value.id);
	if (id === null || typeof value.title !== "string") {
		return null;
	}
	return { id, title: value.title };
}

export function parseUploadJob(body: unknown): UploadJob {
	if (!isRecord(body)) {
		throw new Error("Invalid upload status");
	}
	const id = positiveInteger(body.id);
	if (id === null || typeof body.status !== "string") {
		throw new Error("Invalid upload status");
	}
	return {
		id,
		status: body.status,
		error: typeof body.error === "string" ? body.error : null,
		duplicate: parseDuplicate(body.duplicate),
		media:
			body.media === null || body.media === undefined
				? null
				: mediaSchema.parse(body.media),
		progress:
			body.progress === null || body.progress === undefined
				? null
				: nullableNumber(body.progress),
		speed: nullableNumber(body.speed),
		etaSeconds: nullableNumber(body.eta_seconds),
	};
}

export function uploadJobPath(job: UploadJobRef): string {
	return job.kind === "transcode"
		? `/media/transcodes/${job.id}`
		: `/media/uploads/${job.id}`;
}

export async function fetchUploadJob(job: UploadJobRef): Promise<UploadJob> {
	const body = await apiFetch<unknown>(uploadJobPath(job));
	return parseUploadJob(body);
}

export async function cancelUploadJob(job: UploadJobRef): Promise<void> {
	await apiFetch<unknown>(uploadJobPath(job), { method: "DELETE" });
}

// Отмена пользователем или уходом с экрана. Отдельный класс, чтобы очередь
// не показывала её как сетевую ошибку.
export class UploadAbortedError extends Error {
	constructor() {
		super("Upload aborted");
		this.name = "UploadAbortedError";
	}
}

export class UploadTimeoutError extends Error {
	constructor() {
		super("Upload timed out");
		this.name = "UploadTimeoutError";
	}
}

export type UploadFailureKind =
	| "timeout"
	| "tooLarge"
	| "rateLimited"
	| "network"
	| "failed";

// Единая классификация ошибок загрузки: хук переводит kind в локализованный
// текст, не разбирая английские сообщения backend по строке.
export function classifyUploadError(error: unknown): UploadFailureKind {
	if (error instanceof UploadTimeoutError) {
		return "timeout";
	}
	if (error instanceof ApiError) {
		if (error.status === 413) {
			return "tooLarge";
		}
		if (error.status === 429) {
			return "rateLimited";
		}
		if (error.status === 408) {
			return "timeout";
		}
		if (error.status === 0) {
			return "network";
		}
	}
	return "failed";
}

function parseErrorBody(text: string): unknown {
	if (text.length === 0) {
		return null;
	}
	try {
		return JSON.parse(text);
	} catch {
		return null;
	}
}

function toUploadError(status: number, text: string): ApiError {
	const body = parseErrorBody(text);
	const message =
		isRecord(body) && typeof body.error === "string" && body.error.length > 0
			? body.error
			: `HTTP ${status}`;
	return new ApiError(status, message, body);
}

interface XhrResult {
	readonly status: number;
	readonly text: string;
}

interface XhrOptions {
	readonly url: string;
	readonly headers: Record<string, string>;
	readonly form: FormData;
	readonly onProgress: (progress: number) => void;
	readonly register: (xhr: XMLHttpRequest | null) => void;
	readonly isAborted: () => boolean;
}

function sendXhr({
	url,
	headers,
	form,
	onProgress,
	register,
	isAborted,
}: XhrOptions): Promise<XhrResult> {
	return new Promise<XhrResult>((resolve, reject) => {
		const xhr = new XMLHttpRequest();
		register(xhr);
		xhr.open("POST", url, true);
		xhr.timeout = UPLOAD_TIMEOUT_MS;
		xhr.setRequestHeader("Accept", "application/json");
		for (const [name, value] of Object.entries(headers)) {
			xhr.setRequestHeader(name, value);
		}
		xhr.upload.onprogress = (event: ProgressEvent) => {
			const percent = progressPercent(event.loaded, event.total);
			if (percent !== null) {
				onProgress(percent);
			}
		};
		xhr.upload.onloadstart = () => onProgress(0);
		xhr.onerror = () => {
			register(null);
			reject(new ApiError(0, "Network request failed"));
		};
		xhr.onabort = () => {
			register(null);
			reject(new UploadAbortedError());
		};
		xhr.ontimeout = () => {
			register(null);
			reject(new UploadTimeoutError());
		};
		xhr.onload = () => {
			register(null);
			resolve({ status: xhr.status, text: xhr.responseText ?? "" });
		};
		xhr.send(form);
		if (isAborted()) {
			xhr.abort();
		}
	});
}

export interface UploadTask {
	readonly promise: Promise<UploadJobRef>;
	readonly abort: () => void;
}

// Один файл: POST /media/upload с Bearer и прогрессом XHR. На 401 —
// одна предварительная apiFetch-проверка (она обновит токен через общий
// transport.refresh) и ровно один повтор с перечитанными заголовками.
export function startUpload(
	source: UploadSource,
	options: {
		force?: boolean;
		onProgress?: (progress: number) => void;
	} = {},
): UploadTask {
	let aborted = false;
	let current: XMLHttpRequest | null = null;
	const onProgress = options.onProgress ?? (() => undefined);

	const buildForm = (): FormData => {
		const form = new FormData();
		// React Native FormData принимает {uri,name,type}; DOM-типы ждут Blob.
		form.append("file", {
			uri: source.uri,
			name: source.name,
			type: source.type,
		} as unknown as Blob);
		form.append("media_type", source.mediaType);
		if (options.force === true) {
			form.append("force", "true");
		}
		return form;
	};

	const attempt = async (allowRetry: boolean): Promise<UploadJobRef> => {
		if (aborted) {
			throw new UploadAbortedError();
		}
		const config = getApiConfig();
		const headers = await config.transport.authHeaders();
		if (aborted) {
			throw new UploadAbortedError();
		}
		const result = await sendXhr({
			url: `${config.baseUrl}/media/upload`,
			headers,
			form: buildForm(),
			onProgress,
			register: (xhr) => {
				current = xhr;
			},
			isAborted: () => aborted,
		});
		if (result.status >= 200 && result.status < 300) {
			return parseEnqueueResponse(
				parseErrorBody(result.text),
				source.mediaType,
			);
		}
		if (result.status === 401 && allowRetry) {
			// apiFetch сам обновит пару токенов; после него перечитываем
			// заголовки. Если refresh не удался, его ошибка информативнее
			// исходного 401.
			await apiFetch<unknown>("/media");
			if (aborted) {
				throw new UploadAbortedError();
			}
			return attempt(false);
		}
		throw toUploadError(result.status, result.text);
	};

	const promise = attempt(true);
	return {
		promise,
		abort: () => {
			aborted = true;
			current?.abort();
			current = null;
		},
	};
}

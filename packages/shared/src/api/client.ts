import { z } from "zod";
import { getApiConfig, RefreshError } from "./transport";

// ApiError keeps the HTTP status and the parsed body: the UI needs to tell
// "not found" from "unauthorized" without parsing strings.
export class ApiError extends Error {
	readonly status: number;
	readonly details: unknown;

	constructor(status: number, message: string, details: unknown = null) {
		super(message);
		this.name = "ApiError";
		this.status = status;
		this.details = details;
	}
}

function extractErrorMessage(status: number, body: unknown): string {
	if (typeof body === "object" && body !== null && "error" in body) {
		const message = (body as { error?: unknown }).error;
		if (typeof message === "string" && message.length > 0) {
			return message;
		}
	}
	return `HTTP ${status}`;
}

async function toApiError(response: Response): Promise<ApiError> {
	let body: unknown = null;
	try {
		body = await response.json();
	} catch {
		// Тело не JSON: для сообщения достаточно статуса.
	}
	return new ApiError(
		response.status,
		extractErrorMessage(response.status, body),
		body,
	);
}

// Публичные auth-эндпоинты и health: обновлять по ним нечего, повтор бессмысленен.
const AUTH_PUBLIC_PATHS = [
	"/auth/request-code",
	"/auth/verify-code",
	"/auth/refresh",
	"/auth/logout-refresh",
	"/health",
];

const PATH_QUERY_SPLIT = /[?#]/;
const TRAILING_SLASHES = /\/+$/;

// Путь с query/fragment или хвостовым слэшем — всё тот же эндпоинт:
// сравниваем нормализованный pathname, иначе публичный вызов начнёт
// пытаться обновить сессию.
function isPublicAuthPath(path: string): boolean {
	const pathname =
		path.split(PATH_QUERY_SPLIT, 1)[0]?.replace(TRAILING_SLASHES, "") ?? "";
	return AUTH_PUBLIC_PATHS.includes(pathname);
}

// Общий промис обновления, чтобы пачка параллельных 401 не плодила
// гонку refresh-запросов.
let refreshInflight: Promise<void> | null = null;
let refreshInflightEpoch = 0;

// Зависший refresh (оборванный NAT/TCP) иначе навсегда блокирует все
// последующие 401: они ждут один и тот же промис.
const REFRESH_TIMEOUT_MS = 30_000;

function sessionEpoch(): number {
	return getApiConfig().sessionEpoch?.() ?? 0;
}

function scheduleRefresh(): Promise<void> {
	// Поколение сессии входит в идентичность промиса: после logout/смены
	// сервера нельзя переиспользовать refresh старого поколения, иначе его
	// ответ запишет токены уже после очистки.
	const epoch = sessionEpoch();
	if (refreshInflight === null || refreshInflightEpoch !== epoch) {
		refreshInflightEpoch = epoch;
		const config = getApiConfig();
		const controller = new AbortController();
		const timer = setTimeout(() => controller.abort(), REFRESH_TIMEOUT_MS);
		// Сырой вызов транспорта без рекурсии в apiFetch: refresh сам себя обновлять не должен.
		// Не привязываем общий refresh к signal первого запроса: его отмена
		// не должна отменять refresh для всех ожидающих.
		refreshInflight = config.transport
			.refresh(config.baseUrl, controller.signal)
			.finally(() => {
				clearTimeout(timer);
				if (refreshInflightEpoch === epoch) {
					refreshInflight = null;
				}
			});
	}
	return refreshInflight;
}

// Вызывать только как apiFetch<unknown> с последующим zod-парсингом.
// Каст результата через `as T` без валидации новому коду запрещён:
// контракт ответа фиксирует схема, а не утверждение типа.
export function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
	return requestWithRefresh<T>(path, init, true, parseJSON);
}

// Бинарные ответы (скачивание оригинала) нужны с тем же refresh-путём,
// что и JSON: сырой fetch падал 401 после истечения access-токена.
export function apiFetchBlob(path: string, init?: RequestInit): Promise<Blob> {
	return requestWithRefresh<Blob>(path, init, true, (response) =>
		response.blob(),
	);
}

type ResponseParser<T> = (response: Response) => Promise<T>;

async function parseJSON<T>(response: Response): Promise<T> {
	if (response.status === 204) {
		return undefined as T;
	}
	const text = await response.text();
	if (text.length === 0) {
		return undefined as T;
	}
	try {
		return JSON.parse(text) as T;
	} catch {
		throw new ApiError(
			response.status,
			"Invalid JSON response",
			text.slice(0, 200),
		);
	}
}

function throwIfAborted(signal?: AbortSignal): void {
	if (signal?.aborted !== true) {
		return;
	}
	// В части полифилов reason — не Error (строка/undefined): нормализуем,
	// иначе вызывающий код получает брошенное «ничего».
	const reason: unknown = signal.reason;
	if (reason instanceof Error) {
		throw reason;
	}
	throw new Error(
		"Aborted",
		reason === undefined ? undefined : { cause: reason },
	);
}

async function requestWithRefresh<T>(
	path: string,
	init: RequestInit | undefined,
	allowRetry: boolean,
	parse: ResponseParser<T>,
): Promise<T> {
	const headers = new Headers(init?.headers);
	if (
		init?.body !== undefined &&
		!(init.body instanceof FormData) &&
		!headers.has("Content-Type")
	) {
		headers.set("Content-Type", "application/json");
	}

	const apiConfig = getApiConfig();
	const authHeaders = await apiConfig.transport.authHeaders();
	for (const [name, value] of Object.entries(authHeaders)) {
		if (!headers.has(name)) {
			headers.set(name, value);
		}
	}

	const response = await fetch(`${apiConfig.baseUrl}${path}`, {
		...init,
		headers,
		credentials: init?.credentials ?? apiConfig.transport.credentials(),
	});

	if (!response.ok) {
		const error = await toApiError(response);
		if (allowRetry && error.status === 401 && !isPublicAuthPath(path)) {
			try {
				await scheduleRefresh();
			} catch (refreshError) {
				// 401/400 на refresh: в другой вкладке куки могли уже
				// обновиться. Один раз повторяем исходный запрос — если
				// сессия действительно мертва, получим тот же 401.
				if (
					refreshError instanceof RefreshError &&
					(refreshError.status === 401 || refreshError.status === 400)
				) {
					throwIfAborted(init?.signal ?? undefined);
					try {
						return await requestWithRefresh<T>(path, init, false, parse);
					} catch (retryError) {
						// Терминальная ошибка — только если и повтор получил
						// 401: иначе платформа зря сбросила бы живую сессию.
						if (retryError instanceof ApiError && retryError.status === 401) {
							await getApiConfig().onAuthFailure?.();
						}
						throw retryError;
					}
				}
				throw refreshError;
			}
			// Ушёл со страницы во время refresh — молча отменяемся,
			// TanStack такое глотает.
			throwIfAborted(init?.signal ?? undefined);
			return requestWithRefresh<T>(path, init, false, parse);
		}
		throw error;
	}

	return parse(response);
}

const healthSchema = z.object({
	status: z.string(),
	version: z.string(),
});

export type HealthResponse = z.infer<typeof healthSchema>;

export async function getHealth(signal?: AbortSignal): Promise<HealthResponse> {
	const body = await apiFetch<unknown>("/health", { signal });
	return healthSchema.parse(body);
}

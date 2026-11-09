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
	"/health",
];

// Общий промис обновления, чтобы пачка параллельных 401 не плодила
// гонку refresh-запросов.
let refreshInflight: Promise<void> | null = null;

function scheduleRefresh(signal?: AbortSignal): Promise<void> {
	if (refreshInflight === null) {
		// Сырой вызов транспорта без рекурсии в apiFetch: refresh сам себя обновлять не должен.
		refreshInflight = getApiConfig()
			.transport.refresh(getApiConfig().baseUrl, signal)
			.finally(() => {
				refreshInflight = null;
			});
	}
	return refreshInflight;
}

// Вызывать только как apiFetch<unknown> с последующим zod-парсингом.
// Каст результата через `as T` без валидации новому коду запрещён:
// контракт ответа фиксирует схема, а не утверждение типа.
export function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
	return requestWithRefresh<T>(path, init, true);
}

async function requestWithRefresh<T>(
	path: string,
	init: RequestInit | undefined,
	allowRetry: boolean,
): Promise<T> {
	const headers = new Headers(init?.headers);
	if (init?.body !== undefined && !(init.body instanceof FormData)) {
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
		if (
			allowRetry &&
			error.status === 401 &&
			!AUTH_PUBLIC_PATHS.includes(path)
		) {
			try {
				await scheduleRefresh(init?.signal ?? undefined);
			} catch (refreshError) {
				// 401/400 на refresh — сессия действительно мертва, отдаём
				// исходный 401. Сеть/5xx/битый ответ — транзиентная ошибка,
				// её нельзя маскировать под «нет сессии».
				if (
					refreshError instanceof RefreshError &&
					(refreshError.status === 401 || refreshError.status === 400)
				) {
					throw error;
				}
				throw refreshError;
			}
			// Ушёл со страницы во время refresh — молча отменяемся,
			// TanStack такое глотает.
			init?.signal?.throwIfAborted();
			return requestWithRefresh<T>(path, init, false);
		}
		throw error;
	}

	// 204 (отмена задания) тела не имеет — json() бросил бы.
	if (response.status === 204) {
		return undefined as T;
	}

	// 200 с пустым телом — тоже пустой результат, а не JSON-ошибка.
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

const healthSchema = z.object({
	status: z.string(),
	version: z.string(),
});

export type HealthResponse = z.infer<typeof healthSchema>;

export async function getHealth(signal?: AbortSignal): Promise<HealthResponse> {
	const body = await apiFetch<unknown>("/health", { signal });
	return healthSchema.parse(body);
}

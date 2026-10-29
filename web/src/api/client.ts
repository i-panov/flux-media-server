import { z } from "zod";

const API_BASE = (import.meta.env.VITE_API_BASE ?? "/api").replace(/\/$/, "");

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

// Публичные auth-эндпоинты: обновлять по ним нечего, повтор бессмысленен.
const AUTH_PUBLIC_PATHS = [
	"/auth/request-code",
	"/auth/verify-code",
	"/auth/refresh",
];

// Общий промис обновления, чтобы пачка параллельных 401 не плодила
// гонку refresh-запросов.
let refreshInflight: Promise<void> | null = null;

async function refreshTokens(): Promise<void> {
	// Сырой fetch без рекурсии в apiFetch: refresh сам себя
	// обновлять не должен.
	const response = await fetch(`${API_BASE}/auth/refresh`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: "{}",
		credentials: "same-origin",
	});
	if (!response.ok) {
		throw new Error(`Token refresh failed: ${response.status}`);
	}
}

function scheduleRefresh(): Promise<void> {
	if (refreshInflight === null) {
		refreshInflight = refreshTokens().finally(() => {
			refreshInflight = null;
		});
	}
	return refreshInflight;
}

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

	const response = await fetch(`${API_BASE}${path}`, {
		...init,
		headers,
		credentials: init?.credentials ?? "same-origin",
	});

	if (!response.ok) {
		const error = await toApiError(response);
		if (
			allowRetry &&
			error.status === 401 &&
			!AUTH_PUBLIC_PATHS.includes(path)
		) {
			try {
				await scheduleRefresh();
			} catch {
				throw error;
			}
			return requestWithRefresh<T>(path, init, false);
		}
		throw error;
	}

	// 204 (отмена задания) тела не имеет — json() бросил бы.
	if (response.status === 204) {
		return undefined as T;
	}

	return (await response.json()) as T;
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

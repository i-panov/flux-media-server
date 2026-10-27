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

export async function apiFetch<T>(
	path: string,
	init?: RequestInit,
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
		let body: unknown = null;
		try {
			body = await response.json();
		} catch {
			// Тело не JSON: для сообщения достаточно статуса.
		}
		throw new ApiError(
			response.status,
			extractErrorMessage(response.status, body),
			body,
		);
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

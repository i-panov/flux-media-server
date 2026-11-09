import type { KeyValueStore } from "../storage";

// AuthTransport закрывает единственное платформенное различие API-слоя:
// web аутентифицируется httpOnly-куками, мобильный клиент — Bearer-токенами
// из защищённого хранилища. HTTP-вызовы (client.ts) платформенно нейтральны.
// Те же литералы, что у fetch, но без зависимости от DOM-типов.
export type CredentialsMode = "omit" | "same-origin" | "include";

export interface AuthTransport {
	authHeaders(): Promise<Record<string, string>>;
	credentials(): CredentialsMode | undefined;
	refresh(baseUrl: string, signal?: AbortSignal): Promise<void>;
}

export function createWebTransport(opts?: {
	credentials?: CredentialsMode;
}): AuthTransport {
	const credentials: CredentialsMode = opts?.credentials ?? "same-origin";
	return {
		authHeaders: (): Promise<Record<string, string>> => Promise.resolve({}),
		credentials: () => credentials,
		refresh: async (baseUrl: string, signal?: AbortSignal) => {
			// Сырой fetch: refresh сам себя обновлять не должен, сервер
			// читает refresh-токен из куки при пустом теле.
			const response = await fetch(`${baseUrl}/auth/refresh`, {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: "{}",
				credentials,
				signal,
			});
			if (!response.ok) {
				throw new RefreshError(
					response.status,
					`Token refresh failed: ${response.status}`,
				);
			}
		},
	};
}

// Отказ именно на refresh, а не исходный 401 запроса. status=0 —
// сеть/битый ответ (транзиентно), 401/400 — refresh-токен невалиден.
export class RefreshError extends Error {
	readonly status: number;

	constructor(status: number, message: string) {
		super(message);
		this.name = "RefreshError";
		this.status = status;
	}
}

export const ACCESS_TOKEN_KEY = "flux.access_token";
export const REFRESH_TOKEN_KEY = "flux.refresh_token";

const MALFORMED_RESPONSE_MESSAGE = "Token refresh failed: malformed response";

export function createTokenTransport(store: KeyValueStore): AuthTransport {
	return {
		authHeaders: async (): Promise<Record<string, string>> => {
			const access = await store.get(ACCESS_TOKEN_KEY);
			return access === null ? {} : { Authorization: `Bearer ${access}` };
		},
		credentials: () => undefined,
		refresh: async (baseUrl: string, signal?: AbortSignal) => {
			const refreshToken = await store.get(REFRESH_TOKEN_KEY);
			if (refreshToken === null) {
				throw new RefreshError(401, "No refresh token stored");
			}
			const response = await fetch(`${baseUrl}/auth/refresh`, {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify({ refresh_token: refreshToken }),
				signal,
			});
			if (!response.ok) {
				// 401/400 — refresh-токен мёртв: пара больше не нужна,
				// иначе каждый старт снова пытается им обновиться.
				if (response.status === 401 || response.status === 400) {
					await store.del(ACCESS_TOKEN_KEY);
					await store.del(REFRESH_TOKEN_KEY);
				}
				throw new RefreshError(
					response.status,
					`Token refresh failed: ${response.status}`,
				);
			}
			const body: unknown = await response.json().catch(() => {
				throw new RefreshError(0, MALFORMED_RESPONSE_MESSAGE);
			});
			if (typeof body !== "object" || body === null) {
				throw new RefreshError(0, MALFORMED_RESPONSE_MESSAGE);
			}
			const { token, refresh_token: nextRefresh } = body as {
				token?: unknown;
				refresh_token?: unknown;
			};
			if (
				typeof token !== "string" ||
				token.length === 0 ||
				typeof nextRefresh !== "string" ||
				nextRefresh.length === 0
			) {
				throw new RefreshError(0, MALFORMED_RESPONSE_MESSAGE);
			}
			await store.set(ACCESS_TOKEN_KEY, token);
			await store.set(REFRESH_TOKEN_KEY, nextRefresh);
		},
	};
}

export interface ApiConfig {
	baseUrl: string;
	transport: AuthTransport;
}

const defaultConfig: ApiConfig = {
	baseUrl: "/api",
	transport: createWebTransport(),
};

let currentConfig: ApiConfig = { ...defaultConfig };

export function configureApi(partial: Partial<ApiConfig>): void {
	currentConfig = { ...currentConfig, ...partial };
}

export function getApiConfig(): ApiConfig {
	return { ...currentConfig };
}

// Только для тестов: сбрасывает конфигурацию к веб-дефолту.
export function resetApiConfig(): void {
	currentConfig = { ...defaultConfig };
}

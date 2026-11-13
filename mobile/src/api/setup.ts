import { configureApi, createTokenTransport } from "@flux/shared";
import { secureStore } from "../storage/secureStore";
import { normalizeServerUrl } from "./serverUrl";

export const SERVER_URL_KEY = "flux.server_url";

export { normalizeServerUrl };

// Адрес из окружения — только для разработки/Expo Go. Без сохранённого
// или заданного адреса приложение не стучится на localhost: корень
// уводит на /server, где поле пустое.
const ENV_BASE_URL = normalizeServerUrl(
	(process.env.EXPO_PUBLIC_API_BASE as string | undefined) ?? "",
);

let serverConfigured = ENV_BASE_URL !== null;

// Импортируется один раз из app/_layout.tsx до любых запросов.
configureApi({
	baseUrl: ENV_BASE_URL ?? "",
	transport: createTokenTransport(secureStore),
	onAuthFailure: () => authFailureHandler?.(),
});

let authFailureHandler: (() => void | Promise<void>) | null = null;

export function setAuthFailureHandler(
	handler: (() => void | Promise<void>) | null,
): void {
	authFailureHandler = handler;
}

export function isServerConfigured(): boolean {
	return serverConfigured;
}

export function applyServerUrl(baseUrl: string): void {
	configureApi({ baseUrl });
	serverConfigured = true;
}

// Подхватывает сохранённый в настройках адрес до первого рендера.
// Ошибка чтения хранилища — остаёмся на дефолте первого кадра.
export async function initApiConfig(): Promise<boolean> {
	try {
		const saved = await secureStore.get(SERVER_URL_KEY);
		const normalized = saved === null ? null : normalizeServerUrl(saved);
		if (normalized !== null) {
			applyServerUrl(normalized);
			return true;
		}
	} catch {
		// Хранилище недоступно — остаёмся без адреса и открываем /server.
	}
	configureApi({ baseUrl: ENV_BASE_URL ?? "" });
	serverConfigured = ENV_BASE_URL !== null;
	return serverConfigured;
}

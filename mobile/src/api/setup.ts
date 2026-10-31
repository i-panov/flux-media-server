import { configureApi, createTokenTransport } from "@flux/shared";
import { secureStore } from "../storage/secureStore";

export const SERVER_URL_KEY = "flux.server_url";

// LAN-адрес машины для Expo Go и эмуляторов задаётся переменной окружения,
// дефолт — локальный бэкенд разработчика (порт по AGENTS.md).
const DEFAULT_BASE_URL =
	(process.env.EXPO_PUBLIC_API_BASE as string | undefined) ??
	"http://localhost:8080/api";

const TRAILING_SLASHES = /\/+$/;

// Нормализация адреса из поля ввода: пробелы и хвостовые слэши режутся,
// принимается только http(s). Невалидному вводу соответствует null.
export function normalizeServerUrl(value: string): string | null {
	const normalized = value.trim().replace(TRAILING_SLASHES, "");
	if (!normalized.startsWith("http://") && !normalized.startsWith("https://")) {
		return null;
	}
	if (normalized === "http://" || normalized === "https://") {
		return null;
	}
	return normalized;
}

// Импортируется один раз из app/_layout.tsx до любых запросов.
configureApi({
	baseUrl: DEFAULT_BASE_URL,
	transport: createTokenTransport(secureStore),
});

// Подхватывает сохранённый в настройках адрес до первого рендера.
// Ошибка чтения хранилища — остаёмся на дефолте первого кадра.
export async function initApiConfig(): Promise<void> {
	try {
		const saved = await secureStore.get(SERVER_URL_KEY);
		const normalized = saved === null ? null : normalizeServerUrl(saved);
		configureApi({ baseUrl: normalized ?? DEFAULT_BASE_URL });
	} catch {
		configureApi({ baseUrl: DEFAULT_BASE_URL });
	}
}

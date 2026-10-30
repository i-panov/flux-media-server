import { configureApi, createTokenTransport } from "@flux/shared";
import { secureStore } from "../storage/secureStore";

// LAN-адрес машины для Expo Go и эмуляторов задаётся переменной окружения,
// дефолт — локальный бэкенд разработчика (порт по AGENTS.md).
const BASE_URL =
	(process.env.EXPO_PUBLIC_API_BASE as string | undefined) ??
	"http://localhost:8080/api";

// Импортируется один раз из app/_layout.tsx до любых запросов.
configureApi({
	baseUrl: BASE_URL,
	transport: createTokenTransport(secureStore),
});

import { Redirect } from "expo-router";

// Корень приложения всегда ведёт в видео; AuthGate внутри табов
// отправит на /login, если сессии нет.
export default function Index() {
	return <Redirect href="/video" />;
}

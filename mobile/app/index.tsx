import { Redirect } from "expo-router";
import { isServerConfigured } from "../src/api/setup";

// Без сохранённого адреса сервера — сразу настройка, без запросов
// на localhost и без ошибки «сервер недоступен». Иначе AuthGate
// внутри табов отправит на /login, если сессии нет.
export default function Index() {
	return <Redirect href={isServerConfigured() ? "/video" : "/server"} />;
}

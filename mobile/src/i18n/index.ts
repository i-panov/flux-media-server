// Минимальный i18n для каркаса: без внешних зависимостей, выбор языка
// по системной локали. Полноценный i18next — отдельный этап.
import { useSyncExternalStore } from "react";

const ru = {
	"common.loading": "Загрузка…",
	"common.retry": "Повторить",
	"common.error": "Ошибка",
	"home.title": "Flux",
	"home.server": "Сервер",
	"home.online": "онлайн",
	"home.offline": "недоступен",
	"home.video": "Видео",
	"home.audio": "Аудио",
	"home.settings": "Настройки",
	"home.logout": "Выйти",
	"login.title": "Вход в Flux",
	"login.subtitle": "Код придёт на почту",
	"login.email": "Email",
	"login.getCode": "Получить код",
	"login.code": "Код из письма",
	"login.signIn": "Войти",
	"login.changeEmail": "Изменить email",
	"login.devCode": "Debug-код: {{code}}",
	"login.invalid": "Неверный или истёкший код",
	"login.error": "Не удалось войти",
	"video.title": "Видео",
	"audio.title": "Аудио",
	"media.empty": "Здесь пока ничего нет",
	"settings.title": "Настройки",
	"settings.server": "Адрес сервера",
	"settings.save": "Сохранить",
	"settings.saving": "Сохранение…",
	"settings.saved": "Адрес сохранён",
	"settings.invalidUrl": "Адрес должен начинаться с http:// или https://",
	"settings.saveError": "Не удалось сохранить адрес",
	"settings.version": "Версия приложения",
	"settings.language": "Язык",
} as const;

const en: Record<keyof typeof ru, string> = {
	"common.loading": "Loading…",
	"common.retry": "Retry",
	"common.error": "Error",
	"home.title": "Flux",
	"home.server": "Server",
	"home.online": "online",
	"home.offline": "offline",
	"home.video": "Video",
	"home.audio": "Audio",
	"home.settings": "Settings",
	"home.logout": "Log out",
	"login.title": "Sign in to Flux",
	"login.subtitle": "We will email you a code",
	"login.email": "Email",
	"login.getCode": "Get code",
	"login.code": "Code from email",
	"login.signIn": "Sign in",
	"login.changeEmail": "Change email",
	"login.devCode": "Debug code: {{code}}",
	"login.invalid": "Invalid or expired code",
	"login.error": "Could not sign in",
	"video.title": "Video",
	"audio.title": "Audio",
	"media.empty": "Nothing here yet",
	"settings.title": "Settings",
	"settings.server": "Server URL",
	"settings.save": "Save",
	"settings.saving": "Saving…",
	"settings.saved": "URL saved",
	"settings.invalidUrl": "URL must start with http:// or https://",
	"settings.saveError": "Could not save URL",
	"settings.version": "App version",
	"settings.language": "Language",
};

export type Language = "ru" | "en";

function detectLanguage(): Language {
	try {
		return Intl.DateTimeFormat()
			.resolvedOptions()
			.locale.toLowerCase()
			.startsWith("ru")
			? "ru"
			: "en";
	} catch {
		return "en";
	}
}

let current: Language = detectLanguage();
const listeners = new Set<() => void>();

export function getLanguage(): Language {
	return current;
}

export function setLanguage(language: Language): void {
	if (current === language) {
		return;
	}
	current = language;
	for (const listener of listeners) {
		listener();
	}
}

function subscribe(listener: () => void): () => void {
	listeners.add(listener);
	return () => {
		listeners.delete(listener);
	};
}

// Реактивная подписка для экранов: t() читает модульную переменную,
// а хук заставляет компонент перерисоваться после setLanguage.
export function useLanguage(): Language {
	return useSyncExternalStore(subscribe, getLanguage, getLanguage);
}

export function t(
	key: keyof typeof ru,
	values?: Record<string, string | number>,
): string {
	let text: string = current === "ru" ? ru[key] : en[key];
	if (values !== undefined) {
		for (const [name, value] of Object.entries(values)) {
			text = text.replaceAll(`{{${name}}}`, String(value));
		}
	}
	return text;
}

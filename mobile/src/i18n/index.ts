// Минимальный i18n для каркаса: без внешних зависимостей, выбор языка
// по системной локали. Полноценный i18next — отдельный этап.
import { useSyncExternalStore } from "react";

const ru = {
	"common.loading": "Загрузка…",
	"common.retry": "Повторить",
	"common.error": "Ошибка",
	"common.back": "Назад",
	"common.cancel": "Отмена",
	"common.close": "Закрыть",
	"home.server": "Сервер",
	"home.offline": "недоступен",
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
	"video.notFound": "Видео не найдено",
	"video.notFoundDescription": "Возможно, оно было удалено.",
	"video.loadError": "Не удалось загрузить видео",
	"video.addToCollection": "В коллекцию",
	"video.sourceLink": "Источник",
	"video.sourceError": "Не удалось открыть ссылку",
	"video.favoriteError": "Не удалось изменить избранное",
	"video.delete": "Удалить",
	"video.deleteTitle": "Удалить видео?",
	"video.deleteConfirm": "Видео переместится в корзину.",
	"video.deleteError": "Не удалось удалить видео",
	"video.meta.year": "Год",
	"video.meta.duration": "Длительность",
	"video.meta.resolution": "Разрешение",
	"video.meta.genre": "Жанр",
	"video.player.play": "Смотреть",
	"video.player.pause": "Пауза",
	"video.player.restart": "Смотреть с начала",
	"video.player.speed": "Скорость",
	"video.player.fullscreen": "На весь экран",
	"video.player.pictureInPicture": "Картинка в картинке",
	"video.player.seekBackward": "Назад на {{seconds}} с",
	"video.player.seekForward": "Вперёд на {{seconds}} с",
	"video.player.timeline": "Позиция воспроизведения",
	"video.player.error": "Не удалось воспроизвести видео",
	"video.player.fullscreenError": "Не удалось открыть полноэкранный режим",
	"video.player.pipError": "Не удалось включить картинку в картинке",
	"collections.addTitle": "Добавить в коллекцию",
	"collections.emptyForType": "Нет коллекций для видео",
	"collections.loadError": "Не удалось загрузить коллекции",
	"collections.addError": "Не удалось добавить в коллекцию",
	"collections.duplicate": "Видео уже в коллекции",
	"audio.title": "Аудио",
	"library.title": "Библиотека",
	"library.hint": "Коллекции и избранное появятся здесь.",
	"library.collections": "Коллекции",
	"library.favorites": "Избранное",
	"library.soon": "Скоро",
	"media.empty": "Здесь пока ничего нет",
	"media.favorite": "В избранное",
	"media.unfavorite": "Убрать из избранного",
	"media.actions": "Действия",
	"settings.title": "Настройки",
	"settings.server": "Адрес сервера",
	"settings.save": "Сохранить",
	"settings.saving": "Сохранение…",
	"settings.saved": "Адрес сохранён",
	"settings.invalidUrl": "Адрес должен начинаться с http:// или https://",
	"settings.saveError": "Не удалось сохранить адрес",
	"settings.version": "Версия приложения",
	"settings.language": "Язык",
	"settings.theme": "Тема",
	"settings.themeSystem": "Системная",
	"settings.themeLight": "Светлая",
	"settings.themeDark": "Тёмная",
	"settings.themeSaved": "Сохранено",
	"server.title": "Сервер",
	"server.hint": "Адрес сервера можно задать до входа.",
	"server.open": "Настроить сервер",
} as const;

const en: Record<keyof typeof ru, string> = {
	"common.loading": "Loading…",
	"common.retry": "Retry",
	"common.error": "Error",
	"common.back": "Back",
	"common.cancel": "Cancel",
	"common.close": "Close",
	"home.server": "Server",
	"home.offline": "offline",
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
	"video.notFound": "Video not found",
	"video.notFoundDescription": "It may have been deleted.",
	"video.loadError": "Could not load the video",
	"video.addToCollection": "Add to collection",
	"video.sourceLink": "Source",
	"video.sourceError": "Could not open the link",
	"video.favoriteError": "Could not update favorites",
	"video.delete": "Delete",
	"video.deleteTitle": "Delete video?",
	"video.deleteConfirm": "The video will be moved to trash.",
	"video.deleteError": "Could not delete the video",
	"video.meta.year": "Year",
	"video.meta.duration": "Duration",
	"video.meta.resolution": "Resolution",
	"video.meta.genre": "Genre",
	"video.player.play": "Play",
	"video.player.pause": "Pause",
	"video.player.restart": "Watch from start",
	"video.player.speed": "Speed",
	"video.player.fullscreen": "Full screen",
	"video.player.pictureInPicture": "Picture in picture",
	"video.player.seekBackward": "Back {{seconds}} s",
	"video.player.seekForward": "Forward {{seconds}} s",
	"video.player.timeline": "Playback position",
	"video.player.error": "Could not play the video",
	"video.player.fullscreenError": "Could not enter full screen",
	"video.player.pipError": "Could not start Picture in Picture",
	"collections.addTitle": "Add to collection",
	"collections.emptyForType": "No collections for video",
	"collections.loadError": "Could not load collections",
	"collections.addError": "Could not add to the collection",
	"collections.duplicate": "The video is already in this collection",
	"audio.title": "Audio",
	"library.title": "Library",
	"library.hint": "Collections and favorites will appear here.",
	"library.collections": "Collections",
	"library.favorites": "Favorites",
	"library.soon": "Soon",
	"media.empty": "Nothing here yet",
	"media.favorite": "Add to favorites",
	"media.unfavorite": "Remove from favorites",
	"media.actions": "Actions",
	"settings.title": "Settings",
	"settings.server": "Server URL",
	"settings.save": "Save",
	"settings.saving": "Saving…",
	"settings.saved": "URL saved",
	"settings.invalidUrl": "URL must start with http:// or https://",
	"settings.saveError": "Could not save URL",
	"settings.version": "App version",
	"settings.language": "Language",
	"settings.theme": "Theme",
	"settings.themeSystem": "System",
	"settings.themeLight": "Light",
	"settings.themeDark": "Dark",
	"settings.themeSaved": "Saved",
	"server.title": "Server",
	"server.hint": "You can set the server URL before signing in.",
	"server.open": "Configure server",
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

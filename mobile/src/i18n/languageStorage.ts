import AsyncStorage from "@react-native-async-storage/async-storage";
import { type Language, parseLanguage } from "./index";

export const LANGUAGE_STORAGE_KEY = "flux.language";

// Отдельный ключ от темы: выбор языка переживает рестарт, а ошибки
// хранилища не должны мешать входу/рендеру (просто остаётся системный).
export async function loadLanguage(): Promise<Language | null> {
	try {
		return parseLanguage(await AsyncStorage.getItem(LANGUAGE_STORAGE_KEY));
	} catch {
		return null;
	}
}

export async function saveLanguage(language: Language): Promise<void> {
	try {
		await AsyncStorage.setItem(LANGUAGE_STORAGE_KEY, language);
	} catch {
		// Недоступное хранилище: язык применится в текущей сессии.
	}
}

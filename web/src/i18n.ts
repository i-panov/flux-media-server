import i18n from "i18next";
import LanguageDetector from "i18next-browser-languagedetector";
import { initReactI18next } from "react-i18next";
import en from "./locales/en.json";
import ru from "./locales/ru.json";

const SUPPORTED_LANGS = ["ru", "en"] as const;
type SupportedLang = (typeof SUPPORTED_LANGS)[number];

function pickLang(raw: string): SupportedLang {
	const base = raw.split("-")[0]?.toLowerCase();
	return base === "en" ? "en" : "ru";
}

void i18n
	.use(LanguageDetector)
	.use(initReactI18next)
	.init({
		resources: {
			en: { translation: en },
			ru: { translation: ru },
		},
		fallbackLng: "ru",
		detection: {
			order: ["localStorage", "navigator"],
			caches: ["localStorage"],
		},
		interpolation: {
			escapeValue: false,
		},
	});

export default i18n;
export type { SupportedLang };
export { pickLang, SUPPORTED_LANGS };

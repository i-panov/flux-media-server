import { t } from "../i18n";

// Тип коллекции — строка из API; неизвестное значение не должно ломать
// подпись, поэтому безопасно падаем в «Видео».
export function collectionTypeLabel(type: string): string {
	if (type === "audio") {
		return t("collections.typeAudio");
	}
	if (type === "image") {
		return t("collections.typeImage");
	}
	return t("collections.typeVideo");
}

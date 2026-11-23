import { Alert } from "react-native";
import { t } from "../i18n";

// Общее подтверждение удаления медиа: одинаковый текст на всех экранах.
export function confirmDeleteMedia(onConfirm: () => void): void {
	Alert.alert(t("video.deleteTitle"), t("video.deleteConfirm"), [
		{ text: t("common.cancel"), style: "cancel" },
		{ text: t("video.delete"), style: "destructive", onPress: onConfirm },
	]);
}

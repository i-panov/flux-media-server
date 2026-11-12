import type { Media } from "@flux/shared";
import * as FileSystem from "expo-file-system/legacy";
import * as Sharing from "expo-sharing";
import { Alert } from "react-native";
import { t } from "../i18n";
import { authSource, streamPath } from "../media/source";

function safeName(media: Media): string {
	const raw = media.filename.trim() === "" ? media.title : media.filename;
	const name = raw.replace(/[\\/:*?"<>|]+/g, "_").trim();
	return name === "" ? `media-${media.id}` : name;
}

// «Сохранить как файл»: тянем оригинал во временный cache и отдаём в
// системный share sheet (Android — «Сохранить в Files», iOS — Files).
export async function saveMediaFile(media: Media): Promise<void> {
	const errorTitle = t("common.error");
	const cache = FileSystem.cacheDirectory;
	if (cache === null) {
		Alert.alert(errorTitle, t("media.saveError"));
		return;
	}
	const target = `${cache}${safeName(media)}`;
	const source = await authSource(streamPath(media.id));
	try {
		await FileSystem.downloadAsync(source.uri, target, {
			headers: source.headers,
		});
		if (!(await Sharing.isAvailableAsync())) {
			Alert.alert(errorTitle, t("media.saveUnavailable"));
			return;
		}
		await Sharing.shareAsync(target, {
			dialogTitle: t("media.saveFile"),
			mimeType:
				media.type === "video"
					? "video/*"
					: media.type === "audio"
						? "audio/*"
						: "image/*",
		});
	} catch {
		Alert.alert(errorTitle, t("media.saveError"));
	}
}

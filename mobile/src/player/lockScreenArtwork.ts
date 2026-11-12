import type { Media } from "@flux/shared";
import * as FileSystem from "expo-file-system/legacy";
import { authSource, coverPath } from "../media/source";

// Системный плеер не умеет отправлять Bearer. Скачиваем обложку в cache
// и отдаём ему локальный file:// URL; ошибки не должны ломать playback.
export async function lockScreenArtwork(
	media: Media,
): Promise<string | undefined> {
	if (media.cover_url === "") return undefined;
	const cache = FileSystem.cacheDirectory;
	if (cache === null) return undefined;
	const target = `${cache}flux-lock-cover-${media.id}.jpg`;
	try {
		const info = await FileSystem.getInfoAsync(target);
		if (info.exists) return target;
		const source = await authSource(coverPath(media.id));
		await FileSystem.downloadAsync(source.uri, target, {
			headers: source.headers,
		});
		return target;
	} catch {
		return undefined;
	}
}

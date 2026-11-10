import * as DocumentPicker from "expo-document-picker";
import {
	createUploadSource,
	isFileTooLarge,
	type UploadSource,
} from "../api/upload";

export interface OversizedUpload {
	readonly name: string;
	readonly size: number;
}

export interface PickedUploadSources {
	readonly sources: UploadSource[];
	/** Сколько выбранных файлов не удалось распознать по MIME/расширению. */
	readonly skipped: number;
	/** Файлы больше backend-лимита: до POST они не доходят. */
	readonly oversized: OversizedUpload[];
	readonly cancelled: boolean;
}

// Системный picker с фильтром video/audio/image. copyToCacheDirectory
// обязателен: XHR читает файл из кэша приложения, а не из чужого provider.
export async function pickUploadSources(): Promise<PickedUploadSources> {
	const result = await DocumentPicker.getDocumentAsync({
		type: ["video/*", "audio/*", "image/*"],
		copyToCacheDirectory: true,
		multiple: true,
	});
	if (result.canceled) {
		return { sources: [], skipped: 0, oversized: [], cancelled: true };
	}
	const sources: UploadSource[] = [];
	const oversized: OversizedUpload[] = [];
	let skipped = 0;
	for (const asset of result.assets) {
		const source = createUploadSource({
			uri: asset.uri,
			name: asset.name,
			mimeType: asset.mimeType,
		});
		if (source === null) {
			skipped += 1;
		} else if (isFileTooLarge(asset.size)) {
			oversized.push({ name: source.name, size: asset.size ?? 0 });
		} else {
			sources.push(source);
		}
	}
	return { sources, skipped, oversized, cancelled: false };
}

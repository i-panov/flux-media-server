import * as FileSystem from "expo-file-system/legacy";
import * as Sharing from "expo-sharing";
import { Platform } from "react-native";
import { type DownloadEntry, downloadFilePath } from "./downloadStore";
import {
	type DownloadExportFailure,
	exportShareOptions,
	exportStagingDirectory,
	exportStagingPath,
} from "./exportStore";

// Удаление staging-каталога не должно затирать результат экспорта: ошибку
// очистки игнорируем, ОС всё равно чистит cacheDirectory.
async function removeExportStaging(directory: string): Promise<void> {
	try {
		await FileSystem.deleteAsync(directory, { idempotent: true });
	} catch {
		// Staging останется в кеше — это не влияет на исходный файл.
	}
}

// Открывает системный share sheet для скачанного файла: на iOS там есть
// «Сохранить в Files», на Android — приложения, умеющие принять файл
// (Files, Drive, мессенджеры). Оригинал после экспорта остаётся в кеше,
// удаляется только временная копия с человеческим именем.
export async function exportDownload(
	entry: DownloadEntry,
	documentDirectory: string | null,
	cacheDirectory: string | null,
	dialogTitle: string,
): Promise<DownloadExportFailure | null> {
	const sourcePath = downloadFilePath(documentDirectory, entry.filename);
	if (sourcePath === null) {
		return "missing";
	}
	try {
		const info = await FileSystem.getInfoAsync(sourcePath);
		if (!info.exists || info.isDirectory) {
			return "missing";
		}
	} catch {
		return "missing";
	}
	const stagingDirectory = exportStagingDirectory(cacheDirectory);
	const stagedPath = exportStagingPath(cacheDirectory, entry);
	if (stagingDirectory === null || stagedPath === null) {
		return "error";
	}
	try {
		if (!(await Sharing.isAvailableAsync())) {
			return "unavailable";
		}
	} catch {
		return "error";
	}
	try {
		await FileSystem.deleteAsync(stagingDirectory, { idempotent: true });
		await FileSystem.makeDirectoryAsync(stagingDirectory, {
			intermediates: true,
		});
		await FileSystem.copyAsync({ from: sourcePath, to: stagedPath });
		await Sharing.shareAsync(
			stagedPath,
			exportShareOptions(entry, dialogTitle, Platform.OS),
		);
		return null;
	} catch {
		return "error";
	} finally {
		await removeExportStaging(stagingDirectory);
	}
}

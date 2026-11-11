import type { Media } from "@flux/shared";
import AsyncStorage from "@react-native-async-storage/async-storage";
import * as FileSystem from "expo-file-system/legacy";
import { type AuthSource, authSource, streamPath } from "../media/source";
import {
	checkDownloadedSize,
	contentLength,
	DOWNLOAD_INDEX_KEY,
	DOWNLOAD_TIMEOUT_MS,
	type DownloadEntry,
	type DownloadFailure,
	type DownloadIndex,
	downloadDirectory,
	downloadFileName,
	downloadFilePath,
	downloadProgressRatio,
	evictDownloads,
	indexMatchesServer,
	isCompleteDownload,
	isDownloadStatusOk,
	normalizeMediaType,
	parseDownloadIndex,
	partPathFor,
	upsertDownloadEntry,
} from "./downloadStore";

// Нативное исполнение скачивания вынесено из DownloadProvider: провайдер
// держит состояние и контексты, а файловые стадии проверяются по шагам
// (.part -> размер/Content-Range -> rename -> индекс).

interface ActiveRef {
	readonly media: { readonly id: number };
	readonly status: "downloading" | "error";
}

interface DownloadHydration {
	readonly isMounted: () => boolean;
	readonly setEntries: (entries: DownloadEntry[]) => void;
	readonly persist: (entries: readonly DownloadEntry[]) => void;
	readonly activeCount: () => number;
}

interface DownloadRun {
	readonly isCurrent: (mediaId: number, token: number) => boolean;
	readonly fail: (mediaId: number, failure: DownloadFailure) => void;
	readonly updateActive: (
		mediaId: number,
		patch: { progress: number | null },
	) => void;
	readonly removeActive: (mediaId: number) => void;
	readonly setEntries: (entries: DownloadEntry[]) => void;
	readonly persist: (entries: readonly DownloadEntry[]) => void;
	readonly tasks: Map<number, FileSystem.DownloadResumable>;
	readonly partPaths: Map<number, string>;
	readonly entries: () => DownloadEntry[];
	readonly active: () => readonly ActiveRef[];
}

async function ensureDownloadDirectory(): Promise<string | null> {
	const directory = downloadDirectory(FileSystem.documentDirectory);
	if (directory === null) {
		return null;
	}
	const info = await FileSystem.getInfoAsync(directory);
	if (!info.exists) {
		await FileSystem.makeDirectoryAsync(directory, { intermediates: true });
	}
	return directory;
}

export async function removeFile(path: string): Promise<void> {
	try {
		await FileSystem.deleteAsync(path, { idempotent: true });
	} catch {
		// Нет файла/нет прав: удаление не должно ломать состояние индекса.
	}
}

export async function clearDownloadDirectory(): Promise<void> {
	const directory = downloadDirectory(FileSystem.documentDirectory);
	if (directory !== null) {
		await removeFile(directory);
	}
}

async function fileExists(path: string): Promise<boolean> {
	try {
		const info = await FileSystem.getInfoAsync(path);
		return info.exists && !info.isDirectory;
	} catch {
		return false;
	}
}

function pathForEntry(entry: DownloadEntry): string | null {
	return downloadFilePath(FileSystem.documentDirectory, entry.filename);
}

// Старт приложения: дочитываем индекс, проверяем сервер, удаляем файлы без
// записи в индексе и осиротевшие .part, затем применяем квоту. Путь каждый
// раз собирается из текущего documentDirectory — iOS мог сменить контейнер.
export async function hydrateDownloads(
	context: DownloadHydration,
	currentServer: string,
): Promise<void> {
	let index: DownloadIndex = { server: null, entries: [] };
	let readFailed = false;
	try {
		index = parseDownloadIndex(await AsyncStorage.getItem(DOWNLOAD_INDEX_KEY));
	} catch {
		readFailed = true;
	}
	// Без прочитанного индекса нельзя отличить свои файлы от чужих:
	// не удаляем каталог и не затираем индекс, следующий запуск восстановит.
	if (readFailed) {
		if (context.isMounted()) {
			context.setEntries([]);
		}
		return;
	}
	let directory: string | null = null;
	try {
		directory = await ensureDownloadDirectory();
	} catch {
		directory = null;
	}
	if (!context.isMounted()) {
		return;
	}
	const accepted = indexMatchesServer(index.server, currentServer)
		? index.entries
		: [];
	if (directory !== null) {
		// Всё, чего нет в принятом индексе, — мусор прошлых версий/серверов.
		const referenced = new Set(accepted.map((entry) => entry.filename));
		try {
			const names = await FileSystem.readDirectoryAsync(directory);
			for (const name of names) {
				if (name.endsWith(".part")) {
					if (context.activeCount() === 0) {
						await removeFile(`${directory}${name}`);
					}
					continue;
				}
				if (!referenced.has(name)) {
					await removeFile(`${directory}${name}`);
				}
			}
		} catch {
			// Каталог мог исчезнуть между вызовами — не критично.
		}
	}
	const present: DownloadEntry[] = [];
	for (const entry of accepted) {
		const path = pathForEntry(entry);
		if (path !== null && (await fileExists(path))) {
			present.push(entry);
		}
	}
	const quota = evictDownloads(present, {});
	for (const evicted of quota.evicted) {
		const path = pathForEntry(evicted);
		if (path !== null) {
			await removeFile(path);
		}
	}
	if (!context.isMounted()) {
		return;
	}
	context.setEntries(quota.kept);
	// Ошибка чтения не должна затирать индекс пустым списком.
	if (!readFailed) {
		context.persist(quota.kept);
	}
}

interface PreparedDownload {
	readonly partPath: string;
	readonly finalPath: string;
	readonly source: AuthSource;
}

async function prepareDownload(
	media: Media,
	token: number,
	run: DownloadRun,
): Promise<PreparedDownload | null> {
	let directory: string | null;
	try {
		directory = await ensureDownloadDirectory();
	} catch {
		directory = null;
	}
	if (!run.isCurrent(media.id, token)) {
		return null;
	}
	if (directory === null) {
		run.fail(media.id, "storage");
		return null;
	}
	const filename = downloadFileName(media);
	const finalPath = downloadFilePath(FileSystem.documentDirectory, filename);
	if (finalPath === null) {
		run.fail(media.id, "storage");
		return null;
	}
	const partPath = partPathFor(finalPath);
	run.partPaths.set(media.id, partPath);
	// Повтор не докачивает старый хвост: начинаем с чистого .part,
	// иначе Range-ответ мог бы смешать байты разных версий файла.
	await removeFile(partPath);
	await removeFile(finalPath);
	if (!run.isCurrent(media.id, token)) {
		await removeFile(partPath);
		return null;
	}
	const source = await authSource(streamPath(media.id)).catch(() => null);
	if (!run.isCurrent(media.id, token)) {
		await removeFile(partPath);
		return null;
	}
	if (source === null) {
		run.fail(media.id, "network");
		return null;
	}
	return { partPath, finalPath, source };
}

async function transferToPart(
	media: Media,
	token: number,
	run: DownloadRun,
	partPath: string,
	source: AuthSource,
	timeoutMs: number,
): Promise<boolean> {
	let lastPercent = Number.NaN;
	const task = FileSystem.createDownloadResumable(
		source.uri,
		partPath,
		{ headers: source.headers },
		(progress) => {
			if (!run.isCurrent(media.id, token)) {
				return;
			}
			const ratio = downloadProgressRatio(
				progress.totalBytesWritten,
				progress.totalBytesExpectedToWrite,
			);
			// При неизвестной длине (null) шлём null, а не 0%: UI покажет
			// спиннер. При известной — обновляемся на каждый целый процент.
			const percent = ratio === null ? -1 : Math.round(ratio * 100);
			if (percent === lastPercent) {
				return;
			}
			lastPercent = percent;
			run.updateActive(media.id, { progress: ratio });
		},
	);
	run.tasks.set(media.id, task);
	let result:
		| Awaited<ReturnType<typeof task.downloadAsync>>
		| "timeout"
		| null = null;
	let timer: ReturnType<typeof setTimeout> | undefined;
	try {
		const download = task.downloadAsync();
		const timeout = new Promise<"timeout">((resolve) => {
			timer = setTimeout(() => {
				void task.cancelAsync().catch(() => undefined);
				resolve("timeout");
			}, timeoutMs);
		});
		result = await Promise.race([download, timeout]);
	} catch {
		result = null;
	} finally {
		if (timer !== undefined) {
			clearTimeout(timer);
		}
		run.tasks.delete(media.id);
		run.partPaths.delete(media.id);
	}
	if (!run.isCurrent(media.id, token)) {
		await removeFile(partPath);
		return false;
	}
	// null — скачивание прервалось исключением, undefined — отмена.
	if (result === null) {
		await removeFile(partPath);
		run.fail(media.id, "network");
		return false;
	}
	if (result === "timeout") {
		// Дожидаемся отмены, иначе нативная запись может воссоздать .part
		// уже после удаления.
		try {
			await task.cancelAsync();
		} catch {
			// Задача уже завершилась.
		}
		await removeFile(partPath);
		run.fail(media.id, "timeout");
		return false;
	}
	if (result === undefined) {
		await removeFile(partPath);
		run.removeActive(media.id);
		return false;
	}
	if (!isDownloadStatusOk(result.status)) {
		await removeFile(partPath);
		run.fail(media.id, "status");
		return false;
	}
	const info = await FileSystem.getInfoAsync(partPath);
	if (!run.isCurrent(media.id, token)) {
		await removeFile(partPath);
		return false;
	}
	if (!info.exists || info.isDirectory) {
		await removeFile(partPath);
		run.fail(media.id, "storage");
		return false;
	}
	// 206 — только целый файл, подтверждённый Content-Range. Content-Length
	// у 206 описывает фрагмент, поэтому одной проверки длины недостаточно.
	if (!isCompleteDownload(result.status, result.headers, info.size)) {
		await removeFile(partPath);
		run.fail(media.id, "size");
		return false;
	}
	if (
		checkDownloadedSize(info.size, contentLength(result.headers)) === "mismatch"
	) {
		await removeFile(partPath);
		run.fail(media.id, "size");
		return false;
	}
	return true;
}

async function commitDownload(
	media: Media,
	token: number,
	run: DownloadRun,
	partPath: string,
	finalPath: string,
): Promise<void> {
	// Отмена могла прийти между transferToPart и commit: не воскрешаем
	// error-состояние и не двигаем уже удалённый .part.
	if (!run.isCurrent(media.id, token)) {
		return;
	}
	const info = await FileSystem.getInfoAsync(partPath);
	if (!run.isCurrent(media.id, token)) {
		return;
	}
	if (!info.exists || info.isDirectory) {
		await removeFile(partPath);
		run.fail(media.id, "storage");
		return;
	}
	await removeFile(finalPath);
	try {
		await FileSystem.moveAsync({ from: partPath, to: finalPath });
	} catch {
		await removeFile(partPath);
		run.fail(media.id, "storage");
		return;
	}
	if (!run.isCurrent(media.id, token)) {
		await removeFile(finalPath);
		return;
	}
	const entry: DownloadEntry = {
		mediaId: media.id,
		title: media.title,
		type: normalizeMediaType(media.type),
		filename: downloadFileName(media),
		size: info.size,
		updatedAt: Date.now(),
	};
	const next = upsertDownloadEntry(run.entries(), entry);
	const activeIds = new Set(
		run
			.active()
			.filter((item) => item.status === "downloading")
			.map((item) => item.media.id),
	);
	const quota = evictDownloads(next, {
		activeIds,
		protectedIds: new Set([media.id]),
	});
	for (const evicted of quota.evicted) {
		const path = pathForEntry(evicted);
		if (path !== null) {
			await removeFile(path);
		}
	}
	if (!run.isCurrent(media.id, token)) {
		return;
	}
	run.setEntries(quota.kept);
	run.persist(quota.kept);
	run.removeActive(media.id);
}

async function executeDownload(
	media: Media,
	token: number,
	run: DownloadRun,
	timeoutMs: number,
): Promise<void> {
	const prepared = await prepareDownload(media, token, run);
	if (prepared === null) {
		return;
	}
	const transferred = await transferToPart(
		media,
		token,
		run,
		prepared.partPath,
		prepared.source,
		timeoutMs,
	);
	if (!transferred) {
		return;
	}
	await commitDownload(
		media,
		token,
		run,
		prepared.partPath,
		prepared.finalPath,
	);
}

// Один прогон: .part -> проверка размера/диапазона -> rename -> индекс.
// Верхний catch гарантирует, что неожиданная ошибка FS/парсера попадёт в
// error-состояние, а не останется unhandled rejection с вечным спиннером.
export async function runDownload(
	media: Media,
	token: number,
	run: DownloadRun,
	timeoutMs: number = DOWNLOAD_TIMEOUT_MS,
): Promise<void> {
	try {
		await executeDownload(media, token, run, timeoutMs);
	} catch {
		const partPath = run.partPaths.get(media.id);
		if (partPath !== undefined) {
			run.partPaths.delete(media.id);
			await removeFile(partPath);
		}
		if (run.isCurrent(media.id, token)) {
			run.fail(media.id, "network");
		}
	}
}

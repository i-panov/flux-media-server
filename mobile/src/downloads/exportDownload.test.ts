import { beforeEach, describe, expect, it, vi } from "vitest";
import type { DownloadEntry } from "./downloadStore";
import { exportDownload } from "./exportDownload";

const mocks = vi.hoisted(() => ({
	getInfoAsync: vi.fn(),
	deleteAsync: vi.fn(),
	makeDirectoryAsync: vi.fn(),
	copyAsync: vi.fn(),
	isAvailableAsync: vi.fn(),
	shareAsync: vi.fn(),
}));

vi.mock("expo-file-system/legacy", () => ({
	getInfoAsync: mocks.getInfoAsync,
	deleteAsync: mocks.deleteAsync,
	makeDirectoryAsync: mocks.makeDirectoryAsync,
	copyAsync: mocks.copyAsync,
}));
vi.mock("expo-sharing", () => ({
	isAvailableAsync: mocks.isAvailableAsync,
	shareAsync: mocks.shareAsync,
}));
vi.mock("react-native", () => ({ Platform: { OS: "android" } }));

const DOCS = "file:///documents/";
const CACHE = "file:///cache/";
const SOURCE = `${DOCS}downloads/media-7.mp4`;
const STAGE_DIR = `${CACHE}flux-export/`;
const STAGE_COPY = `${STAGE_DIR}Медиа 7.mp4`;
const DIALOG = "Поделиться файлом";

function entry(
	type: DownloadEntry["type"] = "video",
	filename = "media-7.mp4",
): DownloadEntry {
	return {
		mediaId: 7,
		title: "Медиа 7",
		type,
		filename,
		size: 1024,
		updatedAt: 1,
	};
}

describe("exportDownload", () => {
	beforeEach(() => {
		vi.clearAllMocks();
		mocks.getInfoAsync.mockResolvedValue({ exists: true, isDirectory: false });
		mocks.deleteAsync.mockResolvedValue(undefined);
		mocks.makeDirectoryAsync.mockResolvedValue(undefined);
		mocks.copyAsync.mockResolvedValue(undefined);
		mocks.isAvailableAsync.mockResolvedValue(true);
		mocks.shareAsync.mockResolvedValue(undefined);
	});

	it("без documentDirectory не трогает нативные модули", async () => {
		await expect(exportDownload(entry(), null, CACHE, DIALOG)).resolves.toBe(
			"missing",
		);
		expect(mocks.getInfoAsync).not.toHaveBeenCalled();
	});

	it("не экспортирует отсутствующий файл", async () => {
		mocks.getInfoAsync.mockResolvedValue({ exists: false });
		await expect(exportDownload(entry(), DOCS, CACHE, DIALOG)).resolves.toBe(
			"missing",
		);
		expect(mocks.copyAsync).not.toHaveBeenCalled();
	});

	it("считает ошибку getInfo отсутствующим файлом", async () => {
		mocks.getInfoAsync.mockRejectedValue(new Error("denied"));
		await expect(exportDownload(entry(), DOCS, CACHE, DIALOG)).resolves.toBe(
			"missing",
		);
		expect(mocks.shareAsync).not.toHaveBeenCalled();
	});

	it("не экспортирует каталог вместо файла", async () => {
		mocks.getInfoAsync.mockResolvedValue({ exists: true, isDirectory: true });
		await expect(exportDownload(entry(), DOCS, CACHE, DIALOG)).resolves.toBe(
			"missing",
		);
		expect(mocks.copyAsync).not.toHaveBeenCalled();
	});

	it("сообщает, если системный share sheet недоступен", async () => {
		mocks.isAvailableAsync.mockResolvedValue(false);
		await expect(exportDownload(entry(), DOCS, CACHE, DIALOG)).resolves.toBe(
			"unavailable",
		);
		expect(mocks.copyAsync).not.toHaveBeenCalled();
		expect(mocks.shareAsync).not.toHaveBeenCalled();
	});

	it("не экспортирует без cacheDirectory", async () => {
		await expect(exportDownload(entry(), DOCS, null, DIALOG)).resolves.toBe(
			"error",
		);
		expect(mocks.copyAsync).not.toHaveBeenCalled();
	});

	it("копирует под человеческим именем и не удаляет оригинал", async () => {
		await expect(
			exportDownload(entry(), DOCS, CACHE, DIALOG),
		).resolves.toBeNull();
		expect(mocks.copyAsync).toHaveBeenCalledWith({
			from: SOURCE,
			to: STAGE_COPY,
		});
		expect(mocks.shareAsync).toHaveBeenCalledWith(STAGE_COPY, {
			mimeType: "video/mp4",
			dialogTitle: DIALOG,
		});
		expect(mocks.deleteAsync).toHaveBeenCalledTimes(2);
		for (const [path] of mocks.deleteAsync.mock.calls) {
			expect(path).toBe(STAGE_DIR);
		}
		expect(mocks.deleteAsync).not.toHaveBeenCalledWith(SOURCE, {
			idempotent: true,
		});
	});

	it("удаляет staging и при ошибке share sheet", async () => {
		mocks.shareAsync.mockRejectedValue(new Error("boom"));
		await expect(exportDownload(entry(), DOCS, CACHE, DIALOG)).resolves.toBe(
			"error",
		);
		expect(mocks.deleteAsync).toHaveBeenLastCalledWith(STAGE_DIR, {
			idempotent: true,
		});
	});

	it("ошибку копирования возвращает как error и чистит staging", async () => {
		mocks.copyAsync.mockRejectedValue(new Error("no space"));
		await expect(exportDownload(entry(), DOCS, CACHE, DIALOG)).resolves.toBe(
			"error",
		);
		expect(mocks.shareAsync).not.toHaveBeenCalled();
		expect(mocks.deleteAsync).toHaveBeenLastCalledWith(STAGE_DIR, {
			idempotent: true,
		});
	});
});

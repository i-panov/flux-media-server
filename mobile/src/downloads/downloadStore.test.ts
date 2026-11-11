import { describe, expect, it } from "vitest";
import {
	checkDownloadedSize,
	contentLength,
	DOWNLOAD_QUOTA_BYTES,
	type DownloadEntry,
	downloadDirectory,
	downloadExtension,
	downloadFileName,
	downloadFilePath,
	downloadProgressRatio,
	evictDownloads,
	findDownloadEntry,
	headerValue,
	indexMatchesServer,
	isCompleteDownload,
	isDownloadStatusOk,
	isSafeDownloadFilename,
	normalizeMediaType,
	parseContentRange,
	parseDownloadIndex,
	partPathFor,
	planDownloadRemoval,
	removeDownloadEntry,
	resolveDownloadedPath,
	serializeDownloadIndex,
	upsertDownloadEntry,
} from "./downloadStore";

const AUDIO = "audio" as const;
const VIDEO = "video" as const;
const DOCS = "file:///documents";
const DOCS_DOWNLOADS = "file:///documents/downloads/";
const DOCS_ROOT = "file:///docs/";
const SERVER = "https://srv.example/api";
const SERVER_A = "https://a/api";
const SERVER_B = "https://b/api";
const MEDIA_7 = "media-7.mp4";
const UNSAFE_NAME = "../evil.mp4";

function entry(
	mediaId: number,
	size: number,
	updatedAt: number,
	type: DownloadEntry["type"] = VIDEO,
): DownloadEntry {
	return {
		mediaId,
		title: `Медиа ${mediaId}`,
		type,
		filename: `media-${mediaId}.mp4`,
		size,
		updatedAt,
	};
}

describe("downloadFileName", () => {
	it("берёт расширение из имени файла, а не только из типа", () => {
		expect(
			downloadFileName({ id: 7, type: VIDEO, filename: "movie.MP4" }),
		).toBe(MEDIA_7);
		expect(
			downloadFileName({ id: 8, type: AUDIO, filename: "extracted.m4a" }),
		).toBe("media-8.m4a");
		expect(
			downloadFileName({ id: 9, type: AUDIO, filename: "track.mp3?x=1" }),
		).toBe("media-9.mp3");
		expect(
			downloadFileName({ id: 10, type: "image", filename: "photo.JPEG" }),
		).toBe("media-10.jpeg");
	});

	it("безопасно откатывается к типу для пустых и странных имён", () => {
		expect(downloadExtension({ type: AUDIO, filename: "" })).toBe(".mp3");
		expect(downloadExtension({ type: VIDEO, filename: "no-extension" })).toBe(
			".mp4",
		);
		expect(downloadExtension({ type: "image", filename: ".jpg" })).toBe(".jpg");
		expect(
			downloadExtension({ type: AUDIO, filename: "../../evil.exe?x" }),
		).toBe(".mp3");
		expect(
			downloadExtension({ type: AUDIO, filename: "song.m4a/../../x" }),
		).toBe(".mp3");
		expect(
			downloadFileName({ id: 11, type: AUDIO, filename: "../../evil.exe" }),
		).toBe("media-11.mp3");
		expect(
			downloadFileName({ id: 12, type: AUDIO, filename: "track.m4a" }),
		).toBe("media-12.m4a");
	});

	it("сводит неизвестный тип к video и .mp4", () => {
		expect(normalizeMediaType("document")).toBe("video");
		expect(normalizeMediaType("audio")).toBe("audio");
		expect(downloadFileName({ id: 13, type: "document", filename: "" })).toBe(
			"media-13.mp4",
		);
	});

	it("строит каталог, путь и .part-путь", () => {
		expect(downloadDirectory(`${DOCS}/`)).toBe(DOCS_DOWNLOADS);
		expect(downloadDirectory(DOCS)).toBe(DOCS_DOWNLOADS);
		expect(downloadDirectory(null)).toBeNull();
		expect(downloadDirectory("")).toBeNull();
		expect(downloadFilePath(DOCS, MEDIA_7)).toBe(
			"file:///documents/downloads/media-7.mp4",
		);
		expect(downloadFilePath(null, MEDIA_7)).toBeNull();
		expect(downloadFilePath(DOCS, UNSAFE_NAME)).toBeNull();
		expect(downloadFilePath(DOCS, "a/b.mp4")).toBeNull();
		expect(partPathFor("file:///downloads/media-7.mp4")).toBe(
			"file:///downloads/media-7.mp4.part",
		);
	});

	it("валидирует имя файла из индекса", () => {
		expect(isSafeDownloadFilename(MEDIA_7)).toBe(true);
		expect(isSafeDownloadFilename("../media-7.mp4")).toBe(false);
		expect(isSafeDownloadFilename("a/b.mp4")).toBe(false);
		expect(isSafeDownloadFilename(".hidden")).toBe(false);
	});
});

describe("download response validation", () => {
	it("находит Content-Length без учёта регистра", () => {
		expect(headerValue({ "Content-Length": "123" }, "content-length")).toBe(
			"123",
		);
		expect(contentLength({ "content-length": "0" })).toBe(0);
		expect(contentLength({ "Content-Length": " 42 " })).toBe(42);
		expect(contentLength({})).toBeNull();
		expect(contentLength({ "content-length": "oops" })).toBeNull();
		expect(contentLength({ "content-length": "" })).toBeNull();
	});

	it("принимает 200/206 и отвергает остальные статусы", () => {
		expect(isDownloadStatusOk(200)).toBe(true);
		expect(isDownloadStatusOk(206)).toBe(true);
		expect(isDownloadStatusOk(401)).toBe(false);
		expect(isDownloadStatusOk(500)).toBe(false);
	});

	it("проверяет фактический размер только при известном Content-Length", () => {
		expect(checkDownloadedSize(100, 100)).toBe("ok");
		expect(checkDownloadedSize(99, 100)).toBe("mismatch");
		expect(checkDownloadedSize(100, null)).toBe("unknown");
		expect(checkDownloadedSize(-1, 100)).toBe("mismatch");
		expect(checkDownloadedSize(1.5, null)).toBe("mismatch");
	});

	it("парсит Content-Range только в строгом формате", () => {
		expect(parseContentRange({ "content-range": "bytes 0-99/100" })).toEqual({
			start: 0,
			end: 99,
			total: 100,
		});
		expect(parseContentRange({ "Content-Range": "bytes 10-19/*" })).toEqual({
			start: 10,
			end: 19,
			total: null,
		});
		expect(parseContentRange({})).toBeNull();
		expect(parseContentRange({ "content-range": "items 0-99/100" })).toBeNull();
	});

	it("не принимает 206-фрагмент за целый файл", () => {
		const full = {
			"content-range": "bytes 0-99/100",
			"content-length": "100",
		};
		expect(isCompleteDownload(200, {}, 100)).toBe(true);
		expect(isCompleteDownload(206, full, 100)).toBe(true);
		expect(isCompleteDownload(206, full, 50)).toBe(false);
		expect(
			isCompleteDownload(206, { "content-range": "bytes 10-19/100" }, 10),
		).toBe(false);
		expect(isCompleteDownload(206, {}, 100)).toBe(false);
		expect(isCompleteDownload(500, {}, 100)).toBe(false);
	});

	it("не отдаёт 0% при неизвестной длине", () => {
		expect(downloadProgressRatio(50, 100)).toBe(0.5);
		expect(downloadProgressRatio(150, 100)).toBe(1);
		expect(downloadProgressRatio(50, -1)).toBeNull();
		expect(downloadProgressRatio(50, 0)).toBeNull();
		expect(downloadProgressRatio(50, Number.NaN)).toBeNull();
	});
});

describe("download index", () => {
	it("сериализует записи и сервер", () => {
		const entries = [entry(1, 10, 100), entry(2, 20, 300)];
		const restored = parseDownloadIndex(
			serializeDownloadIndex(entries, SERVER),
		);
		expect(restored.server).toBe(SERVER);
		expect(restored.entries.map((item) => item.mediaId)).toEqual([2, 1]);
		expect(restored.entries[0]).toMatchObject({
			title: "Медиа 2",
			filename: "media-2.mp4",
			size: 20,
		});
	});

	it("битый JSON и чужая версия дают пустой индекс", () => {
		expect(parseDownloadIndex("{oops")).toEqual({ server: null, entries: [] });
		expect(parseDownloadIndex(null)).toEqual({ server: null, entries: [] });
		expect(parseDownloadIndex("")).toEqual({ server: null, entries: [] });
		expect(
			parseDownloadIndex(JSON.stringify({ version: 2, items: [] })),
		).toEqual({ server: null, entries: [] });
		expect(parseDownloadIndex(JSON.stringify({ version: 1 }))).toEqual({
			server: null,
			entries: [],
		});
	});

	it("мигрирует legacy path в filename и сохраняет прежние файлы", () => {
		const restored = parseDownloadIndex(
			JSON.stringify({
				version: 1,
				items: [
					{
						...entry(5, 10, 100, AUDIO),
						path: "file:///old/container/downloads/media-5.m4a",
						filename: undefined,
					},
				],
			}),
		);
		expect(restored.entries[0]?.filename).toBe("media-5.m4a");
		expect(restored.server).toBeNull();
	});

	it("отбрасывает невалидные записи и схлопывает дубликаты", () => {
		const restored = parseDownloadIndex(
			JSON.stringify({
				version: 1,
				server: SERVER,
				items: [
					entry(1, 10, 100),
					{ ...entry(2, 20, 200), filename: UNSAFE_NAME },
					{ ...entry(3, 20, 200), size: -1 },
					{ ...entry(4, 20, 200), type: "document" },
					{ ...entry(1, 99, 300), title: "Новая версия" },
				],
			}),
		);
		expect(restored.entries).toHaveLength(1);
		expect(restored.entries[0]).toMatchObject({
			mediaId: 1,
			title: "Новая версия",
			size: 99,
		});
	});

	it("различает сервер, но принимает legacy-индекс без server", () => {
		expect(indexMatchesServer(null, SERVER_A)).toBe(true);
		expect(indexMatchesServer(SERVER_A, SERVER_A)).toBe(true);
		expect(indexMatchesServer(SERVER_A, SERVER_B)).toBe(false);
	});

	it("резолвит путь по mediaId из текущего каталога и не отдаёт чужой файл", () => {
		const entries = [entry(1, 10, 100), entry(2, 20, 200)];
		expect(resolveDownloadedPath(entries, true, 1, DOCS_ROOT)).toBe(
			"file:///docs/downloads/media-1.mp4",
		);
		expect(resolveDownloadedPath(entries, true, 2, DOCS_ROOT)).toBe(
			"file:///docs/downloads/media-2.mp4",
		);
		expect(resolveDownloadedPath(entries, true, 3, DOCS_ROOT)).toBeNull();
		expect(resolveDownloadedPath(entries, false, 1, DOCS_ROOT)).toBeNull();
	});

	it("добавляет, заменяет и удаляет запись", () => {
		const initial = [entry(1, 10, 100), entry(2, 20, 200)];
		const replaced = upsertDownloadEntry(initial, entry(2, 50, 300));
		expect(replaced.map((item) => item.mediaId)).toEqual([2, 1]);
		expect(replaced[0].size).toBe(50);
		expect(findDownloadEntry(replaced, 2)?.size).toBe(50);
		expect(findDownloadEntry(replaced, 9)).toBeNull();
		expect(
			removeDownloadEntry(replaced, 2).map((item) => item.mediaId),
		).toEqual([1]);
	});

	it("планирует удаление записи и файла, не мутируя исходный индекс", () => {
		const initial = [entry(1, 10, 100), entry(2, 20, 200)];
		const plan = planDownloadRemoval(initial, 1, DOCS_ROOT);
		expect(plan.entry?.mediaId).toBe(1);
		expect(plan.next.map((item) => item.mediaId)).toEqual([2]);
		expect(plan.path).toBe("file:///docs/downloads/media-1.mp4");
		expect(initial.map((item) => item.mediaId)).toEqual([1, 2]);
	});

	it("без записи не планирует удаление файла", () => {
		const initial = [entry(1, 10, 100)];
		const plan = planDownloadRemoval(initial, 9, DOCS_ROOT);
		expect(plan.entry).toBeNull();
		expect(plan.next.map((item) => item.mediaId)).toEqual([1]);
		expect(plan.path).toBeNull();
	});

	it("удаляет запись даже при небезопасном имени в битом индексе", () => {
		const broken = { ...entry(1, 10, 100), filename: UNSAFE_NAME };
		const plan = planDownloadRemoval([broken], 1, DOCS_ROOT);
		expect(plan.entry?.mediaId).toBe(1);
		expect(plan.next).toEqual([]);
		expect(plan.path).toBeNull();
	});
});

describe("download quota", () => {
	it("вытесняет самый старый завершённый файл до лимита", () => {
		const result = evictDownloads(
			[entry(1, 40, 100), entry(2, 40, 200), entry(3, 40, 300)],
			{ quotaBytes: 100 },
		);
		expect(result.evicted.map((item) => item.mediaId)).toEqual([1]);
		expect(result.kept.map((item) => item.mediaId)).toEqual([2, 3]);
		expect(result.totalBytes).toBe(80);
	});

	it("не трогает активные и защищённые загрузки", () => {
		const result = evictDownloads(
			[entry(1, 40, 100), entry(2, 40, 200), entry(3, 40, 300)],
			{
				quotaBytes: 0,
				activeIds: new Set([1]),
				protectedIds: new Set([3]),
			},
		);
		expect(result.evicted.map((item) => item.mediaId)).toEqual([2]);
		expect(result.kept.map((item) => item.mediaId)).toEqual([1, 3]);
	});

	it("оставляет превышение, если все файлы защищены", () => {
		const result = evictDownloads([entry(1, 200, 100)], {
			quotaBytes: 100,
			activeIds: new Set([1]),
		});
		expect(result.evicted).toEqual([]);
		expect(result.totalBytes).toBe(200);
	});

	it("по умолчанию использует лимит 2 ГиБ", () => {
		const result = evictDownloads(
			[
				entry(1, DOWNLOAD_QUOTA_BYTES, 100),
				entry(2, DOWNLOAD_QUOTA_BYTES, 200),
			],
			{},
		);
		expect(result.evicted.map((item) => item.mediaId)).toEqual([1]);
	});
});

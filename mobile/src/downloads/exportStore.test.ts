import { describe, expect, it } from "vitest";
import type { DownloadEntry } from "./downloadStore";
import {
	downloadMimeType,
	exportFileName,
	exportShareOptions,
	exportStagingDirectory,
	exportStagingPath,
} from "./exportStore";

const MEDIA_7 = "media-7.mp4";

function entry(
	type: DownloadEntry["type"] = "video",
	filename = MEDIA_7,
	overrides: Partial<DownloadEntry> = {},
): DownloadEntry {
	return {
		mediaId: 7,
		title: "Медиа 7",
		type,
		filename,
		size: 1024,
		updatedAt: 1,
		...overrides,
	};
}

describe("downloadMimeType", () => {
	it("определяет MIME по расширению файла", () => {
		expect(downloadMimeType(entry("video", "media-1.mp4"))).toBe("video/mp4");
		expect(downloadMimeType(entry("video", "media-2.MKV"))).toBe(
			"video/x-matroska",
		);
		expect(downloadMimeType(entry("audio", "media-3.m4a"))).toBe("audio/mp4");
		expect(downloadMimeType(entry("audio", "media-4.flac"))).toBe("audio/flac");
		expect(downloadMimeType(entry("image", "media-5.webp"))).toBe("image/webp");
	});

	it("откатывается к типу media без известного расширения", () => {
		expect(downloadMimeType(entry("video", "media-6.bin"))).toBe("video/mp4");
		expect(downloadMimeType(entry("audio", "media-7"))).toBe("audio/mpeg");
		expect(downloadMimeType(entry("image", "media-8."))).toBe("image/jpeg");
	});
});

describe("exportFileName", () => {
	it("строит человеческое имя и сохраняет расширение", () => {
		expect(
			exportFileName(
				entry("video", "media-7.mkv", {
					title: "Мой фильм: часть 1 / финал?",
				}),
			),
		).toBe("Мой фильм часть 1 финал.mkv");
		expect(
			exportFileName(
				entry("audio", "media-7.m4a", { title: "  Любимый трек  " }),
			),
		).toBe("Любимый трек.m4a");
	});

	it("чистит символы, ломающие file:// URI и имена файлов", () => {
		expect(
			exportFileName(
				entry("video", MEDIA_7, { title: "100% #1: сцена/финал?" }),
			),
		).toBe("100 1 сцена финал.mp4");
	});

	it("не даёт выйти за staging-каталог и не оставляет пустое имя", () => {
		expect(
			exportFileName(entry("video", MEDIA_7, { title: "../../evil" })),
		).toBe("evil.mp4");
		expect(exportFileName(entry("video", MEDIA_7, { title: ".." }))).toBe(
			MEDIA_7,
		);
		expect(
			exportFileName(entry("audio", "media-7.mp3", { title: "   " })),
		).toBe("media-7.mp3");
	});

	it("ограничивает длину, не разрезая emoji, и чистит крайние точки", () => {
		const long = exportFileName(
			entry("video", MEDIA_7, { title: `${"😀".repeat(100)}...` }),
		);
		expect([...long].length).toBe(84);
		expect(long.endsWith(".mp4")).toBe(true);
		expect(long.includes(" ")).toBe(false);
	});
});

describe("staging", () => {
	it("строит отдельный каталог в cacheDirectory", () => {
		expect(exportStagingDirectory("file:///cache")).toBe(
			"file:///cache/flux-export/",
		);
		expect(exportStagingDirectory("file:///cache/")).toBe(
			"file:///cache/flux-export/",
		);
		expect(exportStagingDirectory(null)).toBeNull();
		expect(exportStagingDirectory("")).toBeNull();
	});

	it("кладёт копию под именем из title", () => {
		expect(
			exportStagingPath(
				"file:///cache",
				entry("video", MEDIA_7, { title: "Мой фильм" }),
			),
		).toBe("file:///cache/flux-export/Мой фильм.mp4");
	});

	it("без cacheDirectory путь не строится", () => {
		expect(exportStagingPath(null, entry())).toBeNull();
	});
});

describe("exportShareOptions", () => {
	const dialogTitle = "Поделиться файлом";

	it("на Android передаёт MIME и заголовок share sheet", () => {
		expect(
			exportShareOptions(entry("video", "media-1.mp4"), dialogTitle, "android"),
		).toEqual({
			mimeType: "video/mp4",
			dialogTitle,
		});
	});

	it("на iOS не передаёт MIME: тип берётся из расширения", () => {
		expect(
			exportShareOptions(entry("audio", "media-2.mp3"), dialogTitle, "ios"),
		).toEqual({});
	});
});

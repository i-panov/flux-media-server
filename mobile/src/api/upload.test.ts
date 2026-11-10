import { ApiError } from "@flux/shared";
import { describe, expect, it } from "vitest";
import {
	classifyUploadError,
	createUploadSource,
	fileExtension,
	fileNameFromUri,
	formatFileSize,
	inferMediaType,
	isFileTooLarge,
	MAX_UPLOAD_BYTES,
	parseEnqueueResponse,
	parseUploadJob,
	progressPercent,
	UPLOAD_TIMEOUT_MS,
	UploadTimeoutError,
	uploadJobPath,
	uploadMimeType,
} from "./upload";

function mediaFixture(overrides: Record<string, unknown> = {}) {
	return {
		id: 9,
		title: "Загруженный трек",
		filename: "track.mp3",
		year: 2024,
		description: "",
		type: "audio",
		artists: [],
		album: "",
		genre: "",
		duration: 120,
		width: 0,
		height: 0,
		file_size: 100,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "",
		...overrides,
	};
}

describe("fileExtension", () => {
	it("берёт расширение из имени и пути", () => {
		expect(fileExtension("Movie.MKV")).toBe("mkv");
		expect(fileExtension("/tmp/audio.flac")).toBe("flac");
		expect(fileExtension("no-extension")).toBe("");
		expect(fileExtension(".hidden")).toBe("");
	});

	it("не режет имя по #/? — это символы имени, а не query", () => {
		expect(fileExtension("song#1.mp3")).toBe("mp3");
		expect(fileExtension("what?.flac")).toBe("flac");
	});
});

// biome-ignore lint/security/noSecrets: имя теста, не секрет.
describe("fileNameFromUri", () => {
	it("отрезает query/fragment только у URI", () => {
		expect(fileNameFromUri("content://media/song.MP3?x=1")).toBe("song.MP3");
		expect(fileNameFromUri("file:///cache/clip.mov#frag")).toBe("clip.mov");
		expect(fileNameFromUri("file:///cache/plain.mp4")).toBe("plain.mp4");
	});
});

describe("inferMediaType", () => {
	it("MIME от picker имеет приоритет над расширением", () => {
		expect(inferMediaType("video/mp4", "song.mp3")).toBe("video");
		expect(inferMediaType("AUDIO/MPEG", "clip.mkv")).toBe("audio");
		expect(inferMediaType("image/webp", "file.bin")).toBe("image");
	});

	it("без полезного MIME тип определяется по расширению", () => {
		expect(inferMediaType("application/octet-stream", "song.flac")).toBe(
			"audio",
		);
		expect(inferMediaType(undefined, "photo.JPG")).toBe("image");
		expect(inferMediaType(null, "movie.mp4")).toBe("video");
	});

	it("неизвестный формат не выдаёт себя за медиа", () => {
		expect(inferMediaType("application/pdf", "doc.pdf")).toBeNull();
		expect(inferMediaType(undefined, "README")).toBeNull();
	});
});

describe("uploadMimeType", () => {
	it("сохраняет MIME, совпадающий с типом медиа", () => {
		expect(uploadMimeType("image", "meme.png", "image/png")).toBe("image/png");
	});

	it("подменяет octet-stream по расширению и дефолту", () => {
		expect(
			uploadMimeType("audio", "song.mp3", "application/octet-stream"),
		).toBe("audio/mpeg");
		expect(uploadMimeType("video", "clip.unknownext")).toBe("video/mp4");
	});
});

describe("createUploadSource", () => {
	it("собирает multipart-поля из asset picker", () => {
		expect(
			createUploadSource({
				uri: "file:///cache/clip.mov",
				name: "clip.mov",
				mimeType: "video/quicktime",
			}),
		).toEqual({
			uri: "file:///cache/clip.mov",
			name: "clip.mov",
			type: "video/quicktime",
			mediaType: "video",
		});
	});

	it("восстанавливает имя и MIME из URI без подсказок", () => {
		expect(
			createUploadSource({ uri: "file:///cache/audio.MP3" }),
		).toMatchObject({
			name: "audio.MP3",
			type: "audio/mpeg",
			mediaType: "audio",
		});
	});

	it("неподдерживаемый файл и пустой URI отбрасываются", () => {
		expect(createUploadSource({ uri: "" })).toBeNull();
		expect(
			createUploadSource({ uri: "file:///doc.pdf", name: "doc.pdf" }),
		).toBeNull();
		// MIME-фильтр picker пропускает image/*, но backend не принимает .heic.
		expect(
			createUploadSource({
				uri: "file:///photo.heic",
				name: "photo.heic",
				mimeType: "image/heic",
			}),
		).toBeNull();
	});
});

// biome-ignore lint/security/noSecrets: имя теста, не секрет.
describe("isFileTooLarge", () => {
	it("не блокирует неизвестный/нулевой размер", () => {
		expect(isFileTooLarge(undefined)).toBe(false);
		expect(isFileTooLarge(null)).toBe(false);
		expect(isFileTooLarge(0)).toBe(false);
	});

	it("отклоняет файлы строго больше лимита backend", () => {
		expect(isFileTooLarge(MAX_UPLOAD_BYTES)).toBe(false);
		expect(isFileTooLarge(MAX_UPLOAD_BYTES + 1)).toBe(true);
	});
});

describe("formatFileSize", () => {
	it("формирует человекочитаемый лимит", () => {
		expect(formatFileSize(MAX_UPLOAD_BYTES)).toBe("2 GB");
		expect(formatFileSize(1536)).toBe("1.5 KB");
		expect(formatFileSize(0)).toBe("0 B");
		expect(formatFileSize(Number.NaN)).toBe("0 B");
	});
});

describe("classifyUploadError", () => {
	it("отделяет таймаут от сети и серверных отказов", () => {
		expect(classifyUploadError(new UploadTimeoutError())).toBe("timeout");
		expect(classifyUploadError(new ApiError(408, "timeout"))).toBe("timeout");
		expect(classifyUploadError(new ApiError(413, "too large"))).toBe(
			"tooLarge",
		);
		expect(classifyUploadError(new ApiError(429, "slow down"))).toBe(
			"rateLimited",
		);
		expect(classifyUploadError(new ApiError(0, "network"))).toBe("network");
		expect(classifyUploadError(new ApiError(500, "server"))).toBe("failed");
		expect(classifyUploadError(new Error("boom"))).toBe("failed");
	});

	it("таймаут XHR задан и положителен", () => {
		expect(UPLOAD_TIMEOUT_MS).toBeGreaterThan(0);
	});
});

describe("progressPercent", () => {
	it("считает долю отправленного тела и ограничивает 0–100", () => {
		expect(progressPercent(50, 100)).toBe(50);
		expect(progressPercent(0, 100)).toBe(0);
		expect(progressPercent(150, 100)).toBe(100);
	});

	it("неизвестный размер не даёт процентов", () => {
		expect(progressPercent(10, 0)).toBeNull();
		expect(progressPercent(Number.NaN, 100)).toBeNull();
	});
});

describe("parseEnqueueResponse", () => {
	it("без job_type видео уходит на transcodes, остальное на uploads", () => {
		expect(parseEnqueueResponse({ job_id: 7 }, "video")).toEqual({
			id: 7,
			kind: "transcode",
		});
		expect(parseEnqueueResponse({ job_id: 8 }, "audio")).toEqual({
			id: 8,
			kind: "upload",
		});
	});

	it("явный job_type важнее типа медиа", () => {
		expect(
			parseEnqueueResponse({ job_id: 3, job_type: "upload" }, "video"),
		).toEqual({ id: 3, kind: "upload" });
	});

	it("битый ответ — ошибка, а не задание 0", () => {
		expect(() => parseEnqueueResponse({}, "audio")).toThrow(ApiError);
		expect(() => parseEnqueueResponse({ job_id: "7" }, "audio")).toThrow(
			ApiError,
		);
	});
});

describe("parseUploadJob", () => {
	it("читает done с медиа и прогрессом транскода", () => {
		const job = parseUploadJob({
			id: 3,
			status: "done",
			error: null,
			media: mediaFixture(),
			progress: 100,
			speed: 2.5,
			eta_seconds: 0,
		});
		expect(job.status).toBe("done");
		expect(job.media?.id).toBe(9);
		expect(job.progress).toBe(100);
		expect(job.speed).toBe(2.5);
		expect(job.etaSeconds).toBe(0);
	});

	it("читает duplicate с id и названием существующего файла", () => {
		const job = parseUploadJob({
			id: 4,
			status: "duplicate",
			duplicate: { id: 12, title: "Похожий мем" },
		});
		expect(job.duplicate).toEqual({ id: 12, title: "Похожий мем" });
	});

	it("битый статус не парсится", () => {
		expect(() => parseUploadJob({ id: 0, status: "done" })).toThrow();
		expect(() => parseUploadJob({ id: 1 })).toThrow();
	});
});

describe("uploadJobPath", () => {
	it("выбирает endpoint по типу задания", () => {
		expect(uploadJobPath({ id: 5, kind: "upload" })).toBe("/media/uploads/5");
		expect(uploadJobPath({ id: 5, kind: "transcode" })).toBe(
			"/media/transcodes/5",
		);
	});
});

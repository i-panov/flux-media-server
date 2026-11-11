import { ApiError, apiFetch } from "@flux/shared";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
	coverErrorKey,
	coverMimeType,
	coverUploadFile,
	isCoverTooLarge,
	MAX_COVER_BYTES,
	parseCoverResponse,
	uploadCover,
} from "./cover";

vi.mock("@flux/shared", async (importOriginal) => {
	const actual = await importOriginal<typeof import("@flux/shared")>();
	return { ...actual, apiFetch: vi.fn() };
});

const apiFetchMock = vi.mocked(apiFetch);

beforeEach(() => {
	apiFetchMock.mockReset();
});

afterEach(() => {
	vi.restoreAllMocks();
});

const IMAGE_URI = "file:///cache/IMG_1.HEIC";
const JPEG_MIME = "image/jpeg";
const UPLOAD_ERROR = "cover.uploadError";
const INVALID_TYPE = "cover.invalidType";

// biome-ignore lint/security/noSecrets: имя теста, не секрет.
describe("isCoverTooLarge", () => {
	it("ровно 10 МБ проходит, больше — нет", () => {
		expect(isCoverTooLarge(MAX_COVER_BYTES)).toBe(false);
		expect(isCoverTooLarge(MAX_COVER_BYTES + 1)).toBe(true);
	});

	it("неизвестный размер не блокирует загрузку", () => {
		expect(isCoverTooLarge(undefined)).toBe(false);
		expect(isCoverTooLarge(null)).toBe(false);
	});
});

describe("coverMimeType", () => {
	it("доверяет MIME из picker, если он из allowlist", () => {
		expect(
			coverMimeType({
				uri: IMAGE_URI,
				fileName: "IMG_1.HEIC",
				mimeType: JPEG_MIME,
			}),
		).toBe(JPEG_MIME);
	});

	it("иначе берёт расширение URI (результат crop)", () => {
		expect(
			coverMimeType({
				uri: "file:///cache/cropped.webp",
				mimeType: "application/octet-stream",
			}),
		).toBe("image/webp");
	});

	it("в последнюю очередь смотрит имя файла", () => {
		expect(
			coverMimeType({
				uri: "content://provider/1234",
				fileName: "cover.PNG",
				mimeType: null,
			}),
		).toBe("image/png");
	});

	it("неподдерживаемый формат — null", () => {
		expect(
			coverMimeType({
				uri: "file:///cache/cover.gif",
				fileName: "cover.gif",
				mimeType: "image/gif",
			}),
		).toBeNull();
		expect(coverMimeType({ uri: "content://provider/1234" })).toBeNull();
	});
});

describe("coverUploadFile", () => {
	it("строит multipart-файл с расширением от фактического MIME", () => {
		expect(
			coverUploadFile({
				uri: IMAGE_URI,
				fileName: "Моя обложка.HEIC",
				mimeType: JPEG_MIME,
			}),
		).toEqual({
			uri: IMAGE_URI,
			name: "_.jpg",
			type: JPEG_MIME,
		});
	});

	it("очищает недопустимые символы имени и не оставляет пустое имя", () => {
		expect(
			coverUploadFile({ uri: "content://provider/42", mimeType: "image/png" }),
		).toEqual({
			uri: "content://provider/42",
			name: "42.png",
			type: "image/png",
		});
	});

	it("неподдерживаемый формат не превращается в файл", () => {
		expect(
			coverUploadFile({
				uri: "file:///cache/cover.gif",
				mimeType: "image/gif",
			}),
		).toBeNull();
	});
});

describe("coverErrorKey", () => {
	it("413 — слишком большой файл", () => {
		expect(coverErrorKey(new ApiError(413, "too large"))).toBe(
			"cover.tooLarge",
		);
	});

	it("400 про формат/содержимое и 415 — неподдерживаемый формат", () => {
		expect(
			coverErrorKey(
				new ApiError(
					400,
					"Invalid cover format. Allowed: jpg, jpeg, png, webp",
				),
			),
		).toBe(INVALID_TYPE);
		expect(
			coverErrorKey(new ApiError(400, "Invalid image content. Allowed")),
		).toBe(INVALID_TYPE);
		expect(coverErrorKey(new ApiError(415, "unsupported"))).toBe(INVALID_TYPE);
	});

	it("прочие 400 (нет файла/не прочитан) — общая ошибка загрузки", () => {
		expect(
			coverErrorKey(new ApiError(400, "Cover image file is required")),
		).toBe(UPLOAD_ERROR);
		expect(coverErrorKey(new ApiError(400, "Failed to read cover file"))).toBe(
			UPLOAD_ERROR,
		);
	});

	it("сеть, 401 и 5xx — общая ошибка загрузки", () => {
		expect(coverErrorKey(new Error("network"))).toBe(UPLOAD_ERROR);
		expect(coverErrorKey(new ApiError(401, "unauthorized"))).toBe(UPLOAD_ERROR);
		expect(coverErrorKey(new ApiError(500, "server"))).toBe(UPLOAD_ERROR);
	});
});

describe("parseCoverResponse", () => {
	it("читает cover_url из ответа PUT /media/:id/cover", () => {
		expect(parseCoverResponse({ cover_url: "/api/media/7/cover" })).toBe(
			"/api/media/7/cover",
		);
	});

	it("бросает ошибку на неожиданное тело", () => {
		expect(() => parseCoverResponse(null)).toThrow("Unexpected cover response");
		expect(() => parseCoverResponse({ cover_url: 7 })).toThrow(
			"Unexpected cover response",
		);
	});
});

describe("uploadCover", () => {
	it("шлёт PUT /media/:id/cover с multipart-полем cover", async () => {
		const appendSpy = vi.spyOn(FormData.prototype, "append");
		apiFetchMock.mockResolvedValue({ cover_url: "/api/media/42/cover" });
		const file = {
			uri: "file:///cache/a.jpg",
			name: "a.jpg",
			type: "image/jpeg",
		};
		await expect(uploadCover(42, file)).resolves.toBe("/api/media/42/cover");
		expect(appendSpy).toHaveBeenCalledWith("cover", file);
		const [path, init] = apiFetchMock.mock.calls[0] ?? [];
		expect(path).toBe("/media/42/cover");
		expect(init?.method).toBe("PUT");
		expect(init?.body).toBeInstanceOf(FormData);
	});
});

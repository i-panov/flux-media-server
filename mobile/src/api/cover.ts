import { ApiError, apiFetch } from "@flux/shared";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { fileExtension, fileNameFromUri } from "./upload";

// Сервер принимает JPEG/PNG/WebP до 10 МБ. Pre-check в приложении не
// заменяет проверку backend, но экономит трафик и сразу показывает ошибку.
export const MAX_COVER_BYTES = 10 * 1024 * 1024;

const FILE_EXTENSION_PATTERN = /\.[^.]*$/;
const UNSAFE_FILENAME_PATTERN = /[^A-Za-z0-9._-]+/g;

const MIME_BY_EXTENSION: Record<string, string> = {
	jpg: "image/jpeg",
	jpeg: "image/jpeg",
	png: "image/png",
	webp: "image/webp",
};

const EXTENSION_BY_MIME: Record<string, string> = {
	"image/jpeg": ".jpg",
	"image/png": ".png",
	"image/webp": ".webp",
};

export interface CoverAssetInput {
	uri: string;
	fileName?: string | null;
	mimeType?: string | null;
}

export interface CoverUploadFile {
	uri: string;
	name: string;
	type: string;
}

export type CoverErrorKey =
	| "cover.tooLarge"
	| "cover.invalidType"
	| "cover.uploadError";

export function isCoverTooLarge(size: number | null | undefined): boolean {
	return typeof size === "number" && size > MAX_COVER_BYTES;
}

// MIME после crop может не совпадать с исходным файлом (iOS HEIC ->
// JPEG, Android -> PNG). Поэтому сначала доверяем MIME, если он в
// allowlist, затем расширению URI (результат picker) и только потом
// исходному имени.
export function coverMimeType(input: CoverAssetInput): string | null {
	const mime = input.mimeType?.trim().toLowerCase() ?? "";
	if (EXTENSION_BY_MIME[mime] !== undefined) {
		return mime;
	}
	const uriExtension = fileExtension(fileNameFromUri(input.uri));
	const fromUri = MIME_BY_EXTENSION[uriExtension];
	if (fromUri !== undefined) {
		return fromUri;
	}
	const nameExtension =
		input.fileName === undefined || input.fileName === null
			? ""
			: fileExtension(input.fileName);
	return MIME_BY_EXTENSION[nameExtension] ?? null;
}

function coverBaseName(input: CoverAssetInput): string {
	const raw = input.fileName?.trim() || fileNameFromUri(input.uri) || "cover";
	const base = raw
		.slice(raw.lastIndexOf("/") + 1)
		.replace(FILE_EXTENSION_PATTERN, "");
	const safe = base.replace(UNSAFE_FILENAME_PATTERN, "_").slice(0, 80);
	return safe === "" ? "cover" : safe;
}

// Имя должно иметь расширение из allowlist: backend проверяет его до
// чтения magic bytes. Расширение берём от фактического MIME, а не от
// исходного HEIC/AVIF имени.
export function coverUploadFile(
	input: CoverAssetInput,
): CoverUploadFile | null {
	const type = coverMimeType(input);
	if (type === null) {
		return null;
	}
	return {
		uri: input.uri,
		name: `${coverBaseName(input)}${EXTENSION_BY_MIME[type]}`,
		type,
	};
}

// 400 у cover-роута бывает и «файл не передан/не прочитан», поэтому
// тип-ошибкой считаем только явные сообщения backend про формат/содержимое.
function isCoverTypeMessage(message: string): boolean {
	const text = message.toLowerCase();
	return text.includes("format") || text.includes("content");
}

export function coverErrorKey(error: unknown): CoverErrorKey {
	if (error instanceof ApiError) {
		if (error.status === 413) {
			return "cover.tooLarge";
		}
		if (error.status === 415) {
			return "cover.invalidType";
		}
		if (error.status === 400 && isCoverTypeMessage(error.message)) {
			return "cover.invalidType";
		}
	}
	return "cover.uploadError";
}

export function parseCoverResponse(body: unknown): string {
	if (body !== null && typeof body === "object") {
		const coverUrl = (body as { cover_url?: unknown }).cover_url;
		if (typeof coverUrl === "string") {
			return coverUrl;
		}
	}
	throw new Error("Unexpected cover response");
}

export async function uploadCover(
	mediaId: number,
	file: CoverUploadFile,
): Promise<string> {
	const form = new FormData();
	// React Native FormData принимает {uri,name,type}; DOM-типы ждут Blob.
	form.append("cover", {
		uri: file.uri,
		name: file.name,
		type: file.type,
	} as unknown as Blob);
	const body = await apiFetch<unknown>(`/media/${mediaId}/cover`, {
		method: "PUT",
		body: form,
	});
	return parseCoverResponse(body);
}

export function useUploadCover(mediaId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (file: CoverUploadFile) => uploadCover(mediaId, file),
		onSuccess: () => {
			// URL обложки не меняется, но сервер отдаёт Cache-Control:
			// no-cache; превью в открытом sheet обновляется cache-buster'ом.
			// Списки, избранное и прогресс содержат media.cover_url, поэтому
			// их тоже надо перечитать, иначе возврат покажет старую обложку.
			void queryClient.invalidateQueries({ queryKey: ["media"] });
			void queryClient.invalidateQueries({ queryKey: ["favorites"] });
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
			void queryClient.invalidateQueries({ queryKey: ["progress"] });
		},
	});
}

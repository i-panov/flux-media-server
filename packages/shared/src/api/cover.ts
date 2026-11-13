import { z } from "zod";

export const MAX_COVER_BYTES = 10 * 1024 * 1024;

export const coverResponseSchema = z.object({ cover_url: z.string() });

export function parseCoverResponse(body: unknown): string {
	const parsed = coverResponseSchema.safeParse(body);
	if (!parsed.success) {
		throw new Error("Unexpected cover response");
	}
	return parsed.data.cover_url;
}

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

export function isCoverTooLarge(size: number | null | undefined): boolean {
	return typeof size === "number" && size > MAX_COVER_BYTES;
}

export function fileExtension(name: string): string {
	const match = FILE_EXTENSION_PATTERN.exec(name);
	return match === null ? "" : match[0].slice(1).toLowerCase();
}

export function fileNameFromUri(uri: string): string {
	const clean = uri.split(/[?#]/, 1)[0] ?? uri;
	const part = clean.slice(clean.lastIndexOf("/") + 1);
	try {
		return decodeURIComponent(part);
	} catch {
		return part;
	}
}

export function coverMimeType(input: CoverAssetInput): string | null {
	const mime = input.mimeType?.trim().toLowerCase() ?? "";
	if (EXTENSION_BY_MIME[mime] !== undefined) return mime;
	const fromUri = MIME_BY_EXTENSION[fileExtension(fileNameFromUri(input.uri))];
	if (fromUri !== undefined) return fromUri;
	return MIME_BY_EXTENSION[fileExtension(input.fileName ?? "")] ?? null;
}

export function coverUploadFile(
	input: CoverAssetInput,
): CoverUploadFile | null {
	const type = coverMimeType(input);
	if (type === null) return null;
	const raw = input.fileName?.trim() || fileNameFromUri(input.uri) || "cover";
	const base = raw
		.slice(raw.lastIndexOf("/") + 1)
		.replace(FILE_EXTENSION_PATTERN, "")
		.replace(UNSAFE_FILENAME_PATTERN, "_")
		.slice(0, 80);
	return {
		uri: input.uri,
		name: `${base === "" ? "cover" : base}${EXTENSION_BY_MIME[type]}`,
		type,
	};
}

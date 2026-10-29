import { createFileRoute } from "@tanstack/react-router";
import type { UploadType } from "../api/upload";
import { UploadPage } from "../features/upload/UploadPage";

function parseType(value: unknown): UploadType {
	if (value === "video" || value === "audio" || value === "image") {
		return value;
	}
	return "video";
}

export const Route = createFileRoute("/upload")({
	validateSearch: (search: Record<string, unknown>): { type: UploadType } => ({
		type: parseType(search.type),
	}),
	component: UploadPage,
});

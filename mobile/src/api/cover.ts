import {
	ApiError,
	apiFetch,
	type CoverUploadFile,
	parseCoverResponse as parseSharedCoverResponse,
} from "@flux/shared";
import { useMutation, useQueryClient } from "@tanstack/react-query";

export type { CoverUploadFile } from "@flux/shared";
export {
	coverMimeType,
	coverUploadFile,
	isCoverTooLarge,
	MAX_COVER_BYTES,
} from "@flux/shared";

function isCoverTypeMessage(message: string): boolean {
	const lower = message.toLowerCase();
	return (
		lower.includes("invalid cover format") ||
		lower.includes("invalid image content")
	);
}

export type CoverErrorKey =
	| "cover.tooLarge"
	| "cover.invalidType"
	| "cover.uploadError";

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
	return parseSharedCoverResponse(body);
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

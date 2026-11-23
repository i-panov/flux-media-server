import type { Media } from "@flux/shared";
import type { UploadDestinationValue } from "../components/UploadDestination";

export type CatalogAssignment =
	| { kind: "episode"; seasonID: number; mediaID: number }
	| { kind: "film"; workID: number; mediaID: number }
	| { kind: "franchise"; franchiseID: number; mediaID: number };

// Чистое решение: куда назначить загруженное медиа. null — некуда или
// это не видео (каталог принимает только видео).
export function assignmentFor(
	destination: UploadDestinationValue,
	media: Media | null,
): CatalogAssignment | null {
	if (media === null || media.type !== "video") return null;
	switch (destination.kind) {
		case "series":
			return destination.seasonID === null
				? null
				: {
						kind: "episode",
						seasonID: destination.seasonID,
						mediaID: media.id,
					};
		case "film_series":
			return destination.workID === null
				? null
				: { kind: "film", workID: destination.workID, mediaID: media.id };
		case "franchise":
			return destination.franchiseID === null
				? null
				: {
						kind: "franchise",
						franchiseID: destination.franchiseID,
						mediaID: media.id,
					};
		default:
			return null;
	}
}

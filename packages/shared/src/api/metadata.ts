import { type Media, mediaSchema } from "../core/media";
import { apiFetch } from "./client";

export interface MetadataInput {
	title: string;
	artists: string[];
	album?: string;
	genre?: string;
	year?: number;
	description?: string;
	sourceUrl?: string;
}

export function buildMetadataBody(input: MetadataInput): Record<string, unknown> {
	const body: Record<string, unknown> = {
		title: input.title,
		artists: input.artists,
	};
	if (input.album !== undefined) body.album = input.album;
	if (input.genre !== undefined) body.genre = input.genre;
	if (input.year !== undefined) body.year = input.year;
	if (input.description !== undefined) body.description = input.description;
	if (input.sourceUrl !== undefined) body.source_url = input.sourceUrl;
	return body;
}

export async function updateMetadata(
	mediaId: number,
	input: MetadataInput,
): Promise<Media> {
	const response = await apiFetch<unknown>(`/metadata/${mediaId}`, {
		method: "PUT",
		body: JSON.stringify(buildMetadataBody(input)),
	});
	return mediaSchema.parse(response);
}

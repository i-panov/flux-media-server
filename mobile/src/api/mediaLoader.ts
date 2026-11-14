import { apiFetch } from "@flux/shared";

export interface MediaLoaderJob {
	id: string;
	status:
		| "queued"
		| "downloading"
		| "importing"
		| "processing"
		| "done"
		| "error"
		| "cancelled";
	stage?: string;
	progress?: number;
	error?: string;
	upload_job_id?: number;
	media_id?: number;
	title?: string;
	filename?: string;
}

const STATUSES: readonly MediaLoaderJob["status"][] = [
	"queued",
	"downloading",
	"importing",
	"processing",
	"done",
	"error",
	"cancelled",
];

function parseJob(value: unknown): MediaLoaderJob {
	if (typeof value !== "object" || value === null) {
		throw new Error("Invalid media loader response");
	}
	const record = value as Record<string, unknown>;
	if (
		typeof record.id !== "string" ||
		!STATUSES.includes(record.status as MediaLoaderJob["status"])
	) {
		throw new Error("Invalid media loader response");
	}
	const optionalString = (key: string): string | undefined =>
		typeof record[key] === "string" ? (record[key] as string) : undefined;
	const optionalNumber = (key: string): number | undefined =>
		typeof record[key] === "number" ? (record[key] as number) : undefined;
	return {
		id: record.id,
		status: record.status as MediaLoaderJob["status"],
		stage: optionalString("stage"),
		progress: optionalNumber("progress"),
		error: optionalString("error"),
		upload_job_id: optionalNumber("upload_job_id"),
		media_id: optionalNumber("media_id"),
		title: optionalString("title"),
		filename: optionalString("filename"),
	};
}

export async function startMediaLoader(input: {
	url: string;
	audioOnly: boolean;
	format: string;
	quality: string;
}): Promise<MediaLoaderJob> {
	const body = await apiFetch<unknown>("/admin/downloads", {
		method: "POST",
		body: JSON.stringify({
			url: input.url,
			audio_only: input.audioOnly,
			format: input.format,
			quality: input.audioOnly ? "" : input.quality,
		}),
	});
	return parseJob(body);
}

export async function fetchMediaLoaderJob(id: string): Promise<MediaLoaderJob> {
	return parseJob(await apiFetch<unknown>(`/admin/downloads/${id}`));
}

export async function cancelMediaLoaderJob(id: string): Promise<void> {
	await apiFetch<unknown>(`/admin/downloads/${id}`, { method: "DELETE" });
}

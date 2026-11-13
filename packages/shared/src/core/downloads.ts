import type { MediaType } from "./media";

export const DOWNLOAD_INDEX_KEY = "flux.downloads.v1";
export const DOWNLOAD_INDEX_VERSION = 1;
export const DOWNLOAD_QUOTA_BYTES = 2 * 1024 * 1024 * 1024;
export const DOWNLOAD_DIRECTORY_NAME = "downloads";
export const DOWNLOAD_TIMEOUT_MS = 60 * 60 * 1000;

export type DownloadFailure =
	| "network"
	| "status"
	| "size"
	| "storage"
	| "timeout";

export interface DownloadEntry {
	readonly mediaId: number;
	readonly title: string;
	readonly type: MediaType;
	readonly filename: string;
	readonly size: number;
	readonly updatedAt: number;
}

export interface DownloadIndex {
	readonly server: string | null;
	readonly entries: DownloadEntry[];
}

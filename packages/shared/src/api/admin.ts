import { z } from "zod";
import { apiFetch } from "./client";

// Админские контракты: storage, originals, transcodes, users, maintenance.
// Схемы и запросы общие; клиенты держат только хуки и инвалидации.
export const storageDiskSchema = z.object({
	path: z.string(),
	total_bytes: z.number(),
	free_bytes: z.number(),
	used_bytes: z.number().default(0),
});
export type StorageDisk = z.infer<typeof storageDiskSchema>;

export const storageInfoSchema = z.object({
	disks: z.array(storageDiskSchema),
	video_bytes: z.number(),
	audio_bytes: z.number(),
	originals_bytes: z.number(),
	temp_bytes: z.number(),
	auto_cleanup: z.boolean(),
});
export type StorageInfo = z.infer<typeof storageInfoSchema>;

export const storageSettingsSchema = z.object({
	auto_cleanup: z.boolean(),
});
export type StorageSettings = z.infer<typeof storageSettingsSchema>;

export const originalSchema = z.object({
	name: z.string(),
	size_bytes: z.number(),
	modified: z.string(),
	status: z.string(),
	media_id: z.number().optional(),
	views: z.number(),
});
export type OriginalItem = z.infer<typeof originalSchema>;

export const defaultAdminUserSchema = z.object({
	id: z.number(),
	email: z.string(),
	is_admin: z.boolean(),
	created_at: z.string(),
});
export type AdminUser = z.infer<typeof defaultAdminUserSchema>;

export const transcodeRowSchema = z.object({
	id: z.number(),
	filename: z.string(),
	status: z.string(),
	progress: z.number(),
	error: z.string().nullish(),
});
export type TranscodeRow = z.infer<typeof transcodeRowSchema>;

export const maintenanceStateSchema = z.object({
	running: z.boolean(),
	kind: z.string().optional(),
	generated: z.number(),
	failed: z.number().default(0),
	last_error: z.string().nullish(),
	started_at: z.string().optional(),
	finished_at: z.string().optional(),
});
export type MaintenanceState = z.infer<typeof maintenanceStateSchema>;

export const maintenanceInfoSchema = z.object({
	missing_thumbnails: z.number(),
	missing_covers: z.number(),
	state: maintenanceStateSchema,
});
export type MaintenanceInfo = z.infer<typeof maintenanceInfoSchema>;

const originalListSchema = z.array(originalSchema);
const userListSchema = z.array(defaultAdminUserSchema);
const transcodeListSchema = z.array(transcodeRowSchema);

export type MaintenanceKind = "thumbnails" | "covers";

export async function getStorage(signal?: AbortSignal): Promise<StorageInfo> {
	return storageInfoSchema.parse(
		await apiFetch<unknown>("/admin/storage", { signal }),
	);
}

export async function setAutoCleanup(
	autoCleanup: boolean,
): Promise<StorageSettings> {
	return storageSettingsSchema.parse(
		await apiFetch<unknown>("/admin/storage/settings", {
			method: "PUT",
			body: JSON.stringify({ auto_cleanup: autoCleanup }),
		}),
	);
}

export async function listOriginals(
	signal?: AbortSignal,
): Promise<OriginalItem[]> {
	return originalListSchema.parse(
		await apiFetch<unknown>("/admin/originals", { signal }),
	);
}

export async function deleteOriginal(name: string): Promise<void> {
	await apiFetch<unknown>(`/admin/originals/${encodeURIComponent(name)}`, {
		method: "DELETE",
	});
}

export async function listTranscodes(): Promise<TranscodeRow[]> {
	return transcodeListSchema.parse(
		await apiFetch<unknown>("/admin/transcodes"),
	);
}

export async function cancelTranscode(id: number): Promise<void> {
	await apiFetch<unknown>(`/media/transcodes/${id}`, { method: "DELETE" });
}

export async function retryTranscode(id: number): Promise<void> {
	await apiFetch<unknown>(`/admin/transcodes/${id}/retry`, { method: "POST" });
}

export async function listUsers(signal?: AbortSignal): Promise<AdminUser[]> {
	return userListSchema.parse(
		await apiFetch<unknown>("/admin/users", { signal }),
	);
}

export async function setUserAdmin(
	id: number,
	isAdmin: boolean,
): Promise<AdminUser> {
	return defaultAdminUserSchema.parse(
		await apiFetch<unknown>(`/admin/users/${id}`, {
			method: "PUT",
			body: JSON.stringify({ is_admin: isAdmin }),
		}),
	);
}

export async function deleteUser(id: number): Promise<void> {
	await apiFetch<unknown>(`/admin/users/${id}`, { method: "DELETE" });
}

export async function getMaintenance(): Promise<MaintenanceInfo> {
	return maintenanceInfoSchema.parse(
		await apiFetch<unknown>("/admin/maintenance"),
	);
}

export async function startMaintenance(kind: MaintenanceKind): Promise<void> {
	await apiFetch<unknown>(`/admin/maintenance/${kind}`, { method: "POST" });
}

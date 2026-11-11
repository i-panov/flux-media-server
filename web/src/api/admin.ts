import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";
import { apiFetch, apiFetchBlob } from "./client";

const diskSchema = z.object({
	path: z.string(),
	total_bytes: z.number(),
	free_bytes: z.number(),
	used_bytes: z.number().default(0),
});

const storageSchema = z.object({
	disks: z.array(diskSchema),
	video_bytes: z.number(),
	audio_bytes: z.number(),
	originals_bytes: z.number(),
	temp_bytes: z.number(),
	auto_cleanup: z.boolean(),
});

export type StorageInfo = z.infer<typeof storageSchema>;

const storageSettingsSchema = z.object({
	auto_cleanup: z.boolean(),
});

export type StorageSettings = z.infer<typeof storageSettingsSchema>;

const originalSchema = z.object({
	name: z.string(),
	size_bytes: z.number(),
	modified: z.string(),
	status: z.string(),
	media_id: z.number().optional(),
	views: z.number(),
});

export type OriginalItem = z.infer<typeof originalSchema>;

const originalsSchema = z.array(originalSchema);

const adminUserSchema = z.object({
	id: z.number(),
	email: z.string(),
	is_admin: z.boolean(),
	created_at: z.string(),
});

export type AdminUser = z.infer<typeof adminUserSchema>;

const adminUsersSchema = z.array(adminUserSchema);

export async function getStorage(signal?: AbortSignal): Promise<StorageInfo> {
	const body = await apiFetch<unknown>("/admin/storage", { signal });
	return storageSchema.parse(body);
}

export async function setAutoCleanup(
	autoCleanup: boolean,
): Promise<StorageSettings> {
	const body = await apiFetch<unknown>("/admin/storage/settings", {
		method: "PUT",
		body: JSON.stringify({ auto_cleanup: autoCleanup }),
	});
	return storageSettingsSchema.parse(body);
}

export async function listOriginals(
	signal?: AbortSignal,
): Promise<OriginalItem[]> {
	const body = await apiFetch<unknown>("/admin/originals", { signal });
	return originalsSchema.parse(body);
}

export function downloadOriginal(
	name: string,
	signal?: AbortSignal,
): Promise<Blob> {
	return apiFetchBlob(`/admin/originals/${encodeURIComponent(name)}/download`, {
		signal,
	});
}

export async function deleteOriginal(name: string): Promise<void> {
	await apiFetch<unknown>(`/admin/originals/${encodeURIComponent(name)}`, {
		method: "DELETE",
	});
}

export async function retryTranscode(id: number): Promise<void> {
	await apiFetch<unknown>(`/admin/transcodes/${id}/retry`, {
		method: "POST",
	});
}

export async function listUsers(signal?: AbortSignal): Promise<AdminUser[]> {
	const body = await apiFetch<unknown>("/admin/users", { signal });
	return adminUsersSchema.parse(body);
}

export async function setUserAdmin(
	id: number,
	isAdmin: boolean,
): Promise<AdminUser> {
	const body = await apiFetch<unknown>(`/admin/users/${id}`, {
		method: "PUT",
		body: JSON.stringify({ is_admin: isAdmin }),
	});
	return adminUserSchema.parse(body);
}

export async function deleteUser(id: number): Promise<void> {
	await apiFetch<unknown>(`/admin/users/${id}`, { method: "DELETE" });
}

export function useStorageQuery(options?: { enabled?: boolean }) {
	return useQuery({
		queryKey: ["admin", "storage"],
		queryFn: ({ signal }) => getStorage(signal),
		retry: false,
		refetchOnWindowFocus: false,
		enabled: options?.enabled ?? true,
	});
}

export function useOriginalsQuery(options?: { enabled?: boolean }) {
	return useQuery({
		queryKey: ["admin", "originals"],
		queryFn: ({ signal }) => listOriginals(signal),
		retry: false,
		refetchOnWindowFocus: false,
		enabled: options?.enabled ?? true,
	});
}

export function useAdminUsersQuery(options?: { enabled?: boolean }) {
	return useQuery({
		queryKey: ["admin", "users"],
		queryFn: ({ signal }) => listUsers(signal),
		retry: false,
		refetchOnWindowFocus: false,
		enabled: options?.enabled ?? true,
	});
}

export function useRetryTranscode() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => retryTranscode(id),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "transcodes"] });
		},
	});
}

export function useDeleteOriginal() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (name: string) => deleteOriginal(name),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "originals"] });
			void queryClient.invalidateQueries({ queryKey: ["admin", "storage"] });
		},
	});
}

export function useSetAutoCleanup() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (autoCleanup: boolean) => setAutoCleanup(autoCleanup),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "storage"] });
		},
	});
}

export function useSetUserAdmin() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, isAdmin }: { id: number; isAdmin: boolean }) =>
			setUserAdmin(id, isAdmin),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
		},
	});
}

export function useDeleteUser() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) => deleteUser(id),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
		},
	});
}

import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { z } from "zod";

const userSchema = z.object({
	id: z.number(),
	email: z.string(),
	is_admin: z.boolean(),
	created_at: z.string(),
});

const maintenanceSchema = z.object({
	missing_thumbnails: z.number(),
	missing_covers: z.number(),
	state: z.object({
		running: z.boolean(),
		kind: z.string().optional(),
		generated: z.number(),
		failed: z.number(),
		last_error: z.string().nullish(),
	}),
});

const storageSchema = z.object({
	disks: z.array(
		z.object({
			path: z.string(),
			total_bytes: z.number(),
			free_bytes: z.number(),
			used_bytes: z.number(),
		}),
	),
	video_bytes: z.number(),
	audio_bytes: z.number(),
	originals_bytes: z.number(),
	temp_bytes: z.number(),
	auto_cleanup: z.boolean(),
});

const transcodeSchema = z.object({
	id: z.number(),
	filename: z.string(),
	status: z.string(),
	progress: z.number(),
	error: z.string().nullish(),
});

const originalSchema = z.object({
	name: z.string(),
	size_bytes: z.number(),
	modified: z.string(),
	status: z.string(),
	media_id: z.number().optional(),
	views: z.number(),
});

export type AdminUser = z.infer<typeof userSchema>;
export type MaintenanceInfo = z.infer<typeof maintenanceSchema>;
export type StorageInfo = z.infer<typeof storageSchema>;
export type StorageDisk = z.infer<typeof storageSchema>["disks"][number];
export type TranscodeRow = z.infer<typeof transcodeSchema>;
export type OriginalRow = z.infer<typeof originalSchema>;

export function useAdminUsers() {
	return useQuery({
		queryKey: ["admin", "users"],
		queryFn: async () =>
			z.array(userSchema).parse(await apiFetch<unknown>("/admin/users")),
	});
}

export function useSetUserAdmin() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async ({ id, isAdmin }: { id: number; isAdmin: boolean }) =>
			userSchema.parse(
				await apiFetch<unknown>(`/admin/users/${id}`, {
					method: "PUT",
					body: JSON.stringify({ is_admin: isAdmin }),
				}),
			),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
		},
	});
}

export function useDeleteUser() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<void>(`/admin/users/${id}`, { method: "DELETE" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
		},
	});
}

export function useStorage() {
	return useQuery({
		queryKey: ["admin", "storage"],
		queryFn: async () =>
			storageSchema.parse(await apiFetch<unknown>("/admin/storage")),
	});
}

export function useSetAutoCleanup() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: async (enabled: boolean) =>
			z.object({ auto_cleanup: z.boolean() }).parse(
				await apiFetch<unknown>("/admin/storage/settings", {
					method: "PUT",
					body: JSON.stringify({ auto_cleanup: enabled }),
				}),
			),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "storage"] });
		},
	});
}

export function useTranscodes() {
	return useQuery({
		queryKey: ["admin", "transcodes"],
		queryFn: async () =>
			z
				.array(transcodeSchema)
				.parse(await apiFetch<unknown>("/admin/transcodes")),
		refetchInterval: (query) =>
			(query.state.data ?? []).some(
				(row) => row.status === "processing" || row.status === "queued",
			)
				? 3000
				: false,
	});
}

export function useCancelTranscode() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<void>(`/media/transcodes/${id}`, { method: "DELETE" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "transcodes"] });
		},
	});
}

export function useRetryTranscode() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (id: number) =>
			apiFetch<unknown>(`/admin/transcodes/${id}/retry`, { method: "POST" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "transcodes"] });
		},
	});
}

export function useOriginals() {
	return useQuery({
		queryKey: ["admin", "originals"],
		queryFn: async () =>
			z
				.array(originalSchema)
				.parse(await apiFetch<unknown>("/admin/originals")),
	});
}

export function useDeleteOriginal() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (name: string) =>
			apiFetch<void>(`/admin/originals/${encodeURIComponent(name)}`, {
				method: "DELETE",
			}),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "originals"] });
			void queryClient.invalidateQueries({ queryKey: ["admin", "storage"] });
		},
	});
}

export function useMaintenance() {
	return useQuery({
		queryKey: ["admin", "maintenance"],
		queryFn: async () =>
			maintenanceSchema.parse(await apiFetch<unknown>("/admin/maintenance")),
		refetchInterval: (query) =>
			query.state.data?.state.running === true ? 2000 : false,
	});
}

export function useBackfill(kind: "thumbnails" | "covers") {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: () =>
			apiFetch<unknown>(`/admin/maintenance/${kind}`, { method: "POST" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({
				queryKey: ["admin", "maintenance"],
			});
		},
	});
}

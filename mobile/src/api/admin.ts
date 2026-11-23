import { apiFetch } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export interface AdminUser {
	id: number;
	email: string;
	is_admin: boolean;
	created_at: string;
}

export interface MaintenanceState {
	running: boolean;
	kind?: string;
	generated: number;
	failed: number;
	last_error?: string;
}

export interface MaintenanceInfo {
	missing_thumbnails: number;
	missing_covers: number;
	state: MaintenanceState;
}

export function useAdminUsers() {
	return useQuery({
		queryKey: ["admin", "users"],
		queryFn: () => apiFetch<AdminUser[]>("/admin/users"),
	});
}

export function useSetUserAdmin() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, isAdmin }: { id: number; isAdmin: boolean }) =>
			apiFetch<AdminUser>(`/admin/users/${id}`, {
				method: "PUT",
				body: JSON.stringify({ is_admin: isAdmin }),
			}),
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

export function useMaintenance() {
	return useQuery({
		queryKey: ["admin", "maintenance"],
		queryFn: () => apiFetch<MaintenanceInfo>("/admin/maintenance"),
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

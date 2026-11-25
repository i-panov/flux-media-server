import {
	cancelTranscode,
	deleteOriginal,
	deleteUser,
	getMaintenance,
	getStorage,
	listOriginals,
	listTranscodes,
	listUsers,
	retryTranscode,
	setAutoCleanup,
	setUserAdmin,
	startMaintenance,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type {
	AdminUser,
	MaintenanceInfo,
	OriginalItem as OriginalRow,
	StorageDisk,
	StorageInfo,
	TranscodeRow,
} from "@flux/shared";

export function useAdminUsers() {
	return useQuery({
		queryKey: ["admin", "users"],
		queryFn: () => listUsers(),
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
		mutationFn: deleteUser,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
		},
	});
}

export function useStorage() {
	return useQuery({
		queryKey: ["admin", "storage"],
		queryFn: () => getStorage(),
	});
}

export function useSetAutoCleanup() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: setAutoCleanup,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "storage"] });
		},
	});
}

export function useTranscodes() {
	return useQuery({
		queryKey: ["admin", "transcodes"],
		queryFn: listTranscodes,
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
		mutationFn: cancelTranscode,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "transcodes"] });
		},
	});
}

export function useRetryTranscode() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: retryTranscode,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "transcodes"] });
		},
	});
}

export function useOriginals() {
	return useQuery({
		queryKey: ["admin", "originals"],
		queryFn: () => listOriginals(),
	});
}

export function useDeleteOriginal() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: deleteOriginal,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "originals"] });
			void queryClient.invalidateQueries({ queryKey: ["admin", "storage"] });
		},
	});
}

export function useMaintenance() {
	return useQuery({
		queryKey: ["admin", "maintenance"],
		queryFn: getMaintenance,
		refetchInterval: (query) =>
			query.state.data?.state.running === true ? 2000 : false,
	});
}

export function useBackfill(kind: "thumbnails" | "covers") {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: () => startMaintenance(kind),
		onSuccess: () => {
			void queryClient.invalidateQueries({
				queryKey: ["admin", "maintenance"],
			});
		},
	});
}

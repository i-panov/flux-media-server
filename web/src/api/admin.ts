import {
	deleteOriginal,
	deleteUser,
	getMaintenance,
	getStorage,
	listOriginals,
	listUsers,
	retryTranscode,
	setAutoCleanup,
	setUserAdmin,
	startMaintenance,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type {
	AdminUser,
	OriginalItem,
	StorageInfo,
	StorageSettings,
} from "@flux/shared";

export {
	deleteOriginal,
	deleteUser,
	getStorage,
	listOriginals,
	listUsers,
	retryTranscode,
	setAutoCleanup,
	setUserAdmin,
};

// Прямая same-origin ссылка (web-only): куки уходят сами, файл не
// буферизуется в памяти вкладки.
export function originalDownloadUrl(name: string): string {
	return `/api/admin/originals/${encodeURIComponent(name)}/download`;
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
		mutationFn: retryTranscode,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "transcodes"] });
		},
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

export function useSetAutoCleanup() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: setAutoCleanup,
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
		mutationFn: deleteUser,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
		},
	});
}

export function useMaintenanceQuery(options?: { enabled?: boolean }) {
	return useQuery({
		queryKey: ["admin", "maintenance"],
		queryFn: getMaintenance,
		refetchInterval: (query) =>
			query.state.data?.state.running === true ? 2000 : false,
		retry: false,
		enabled: options?.enabled ?? true,
	});
}

export function useBackfillThumbnails() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: () => startMaintenance("thumbnails"),
		onSuccess: () => {
			void queryClient.invalidateQueries({
				queryKey: ["admin", "maintenance"],
			});
		},
	});
}

export function useBackfillCovers() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: () => startMaintenance("covers"),
		onSuccess: () => {
			void queryClient.invalidateQueries({
				queryKey: ["admin", "maintenance"],
			});
		},
	});
}

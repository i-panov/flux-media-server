import {
	cancelImport,
	fetchImportJob,
	fetchImportJobs,
	probeImport,
	startImport,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type {
	ImportEpisode,
	ImportJob,
	ImportJobDetail,
	ImportProbe,
	ImportProbeEpisode,
} from "@flux/shared";

export function useImportProbe() {
	return useMutation({ mutationFn: probeImport });
}

export function useStartImport() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: startImport,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["import"] });
		},
	});
}

const IMPORT_ACTIVE = new Set(["queued", "downloading", "importing"]);

export function useImportJobs() {
	return useQuery({
		queryKey: ["import", "list"],
		queryFn: fetchImportJobs,
		refetchInterval: (query) =>
			(query.state.data ?? []).some((job) => IMPORT_ACTIVE.has(job.status))
				? 3000
				: false,
	});
}

export function useImportJob(id: number | null) {
	const queryClient = useQueryClient();
	return useQuery({
		queryKey: ["import", id],
		queryFn: async () => {
			const detail = await fetchImportJob(Number(id));
			if (
				detail.job.status !== "queued" &&
				detail.job.status !== "downloading" &&
				detail.job.status !== "importing"
			) {
				void queryClient.invalidateQueries({ queryKey: ["works"] });
				void queryClient.invalidateQueries({ queryKey: ["media"] });
			}
			return detail;
		},
		enabled: id !== null && id > 0,
		refetchInterval: (query) => {
			const status = query.state.data?.job.status;
			return status === "queued" ||
				status === "downloading" ||
				status === "importing"
				? 2000
				: false;
		},
	});
}

export function useCancelImport() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: cancelImport,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["import"] });
		},
	});
}

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
			void queryClient.invalidateQueries({ queryKey: ["works"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

export function useImportJobs() {
	return useQuery({
		queryKey: ["import", "list"],
		queryFn: fetchImportJobs,
		refetchInterval: (query) =>
			(Array.isArray(query.state.data) ? query.state.data : []).some(
				(job) =>
					job.status !== "done" &&
					job.status !== "error" &&
					job.status !== "partial",
			)
				? 3000
				: false,
	});
}

export function useImportJob(id: number | null) {
	return useQuery({
		queryKey: ["import", id],
		queryFn: () => fetchImportJob(Number(id)),
		enabled: id !== null && id > 0,
		refetchInterval: (query) => {
			const status = query.state.data?.job.status;
			return status === "downloading" ||
				status === "importing" ||
				status === "queued"
				? 3000
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
			void queryClient.invalidateQueries({ queryKey: ["works"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		},
	});
}

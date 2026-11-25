import {
	cancelImport,
	fetchImportJob,
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

import {
	cancelMediaLoaderJob,
	fetchMediaLoaderJobs,
	isActiveMediaLoaderJob,
	startMediaLoader,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type { MediaLoaderJob } from "@flux/shared";

export function useMediaLoaderJobs() {
	return useQuery({
		queryKey: ["media-loader"],
		queryFn: fetchMediaLoaderJobs,
		refetchInterval: (query) =>
			(query.state.data ?? []).some(isActiveMediaLoaderJob) ? 2000 : false,
	});
}

export function useStartMediaLoader() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: startMediaLoader,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["media-loader"] });
		},
	});
}

export { cancelMediaLoaderJob };

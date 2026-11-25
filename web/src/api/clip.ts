import { cancelClip, createClip, fetchClip } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

export type { ClipTask } from "@flux/shared";

export function useCreateClip() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: createClip,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["clips"] });
		},
	});
}

export function useCancelClip() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: cancelClip,
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["clips"] });
		},
	});
}

export function useClip(id: number | null) {
	const queryClient = useQueryClient();
	return useQuery({
		queryKey: ["clips", id],
		queryFn: async () => {
			const task = await fetchClip(Number(id));
			if (task.status === "done") {
				void queryClient.invalidateQueries({ queryKey: ["media"] });
			}
			return task;
		},
		enabled: id !== null && id > 0,
		refetchInterval: (query) =>
			query.state.data?.status === "queued" ||
			query.state.data?.status === "processing"
				? 2000
				: false,
	});
}

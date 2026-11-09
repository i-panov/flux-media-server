import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchLyrics, type SaveLyricsInput, saveLyrics } from "./client";

export function useLyrics(mediaId: number, enabled = true) {
	return useQuery({
		queryKey: ["lyrics", mediaId],
		queryFn: () => fetchLyrics(mediaId),
		enabled,
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export function useSaveLyrics(mediaId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: SaveLyricsInput) => saveLyrics(mediaId, input),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["lyrics", mediaId] });
		},
	});
}

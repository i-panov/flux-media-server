import {
	fetchLyrics,
	type Lyrics,
	type SaveLyricsInput,
	saveLyrics,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { hasLyricsContent } from "../lyrics/lyricsView";

// Тот же ключ, что у web: fetchLyrics возвращает null на 404, поэтому
// «текста нет» — это успешный кэш, а не ошибка.
export function lyricsQueryKey(mediaId: number) {
	return ["lyrics", mediaId] as const;
}

// Пустая запись (после очистки) для UI — это отсутствие текста: иначе
// экран показывал бы «Редактировать» для записи без содержимого.
function selectLyrics(lyrics: Lyrics | null): Lyrics | null {
	return hasLyricsContent(lyrics) ? lyrics : null;
}

export function useLyrics(mediaId: number, enabled = true) {
	return useQuery({
		queryKey: lyricsQueryKey(mediaId),
		queryFn: () => fetchLyrics(mediaId),
		enabled: enabled && mediaId > 0,
		retry: false,
		refetchOnWindowFocus: false,
		select: selectLyrics,
	});
}

function isClearingInput(input: SaveLyricsInput): boolean {
	return (
		input.lyricsText.trim() === "" &&
		input.translation.trim() === "" &&
		(input.syncData ?? "").trim() === ""
	);
}

export function useSaveLyrics(mediaId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: SaveLyricsInput) => saveLyrics(mediaId, input),
		onSuccess: (_data, input) => {
			// Очистка сразу отражается в UI; refetch затем подтвердит её
			// (бэкенд может вернуть запись с пустыми полями).
			if (isClearingInput(input)) {
				queryClient.setQueryData<Lyrics | null>(lyricsQueryKey(mediaId), null);
			}
			void queryClient.invalidateQueries({
				queryKey: lyricsQueryKey(mediaId),
			});
		},
	});
}

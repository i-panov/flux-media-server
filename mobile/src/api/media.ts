import {
	apiFetch,
	audioListOptions,
	type CoreFetcher,
	videoListOptions,
} from "@flux/shared";
import { useInfiniteQuery } from "@tanstack/react-query";

// CoreFetcher уже платформенно-нейтрален; транспорт подставляет
// configureApi (Bearer + базовый URL сервера).
const fetcher: CoreFetcher = (path, init) => apiFetch(path, init);

export function useVideoList() {
	return useInfiniteQuery(videoListOptions(fetcher, ""));
}

export function useAudioList() {
	return useInfiniteQuery(audioListOptions(fetcher, ""));
}

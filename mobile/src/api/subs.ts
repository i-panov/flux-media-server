import { apiFetch, type CoreFetcher, mediaSubsOptions } from "@flux/shared";
import { useQuery } from "@tanstack/react-query";

const fetcher: CoreFetcher = (path, init) => apiFetch(path, init);

// Список дорожек субтитров: запрос общий с web, здесь только хук.
export function useMediaSubs(mediaId: number) {
	return useQuery({
		...mediaSubsOptions(fetcher, mediaId),
		enabled: mediaId > 0,
		// Сайдкар может появиться после транскода: без этого CC не
		// появится до повторного открытия видео.
		refetchInterval: (query) =>
			(query.state.data ?? []).length === 0 ? 15_000 : false,
	});
}

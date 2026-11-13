import {
	apiFetch,
	audioListOptions,
	type CoreFetcher,
	imageListOptions,
	mediaOptions,
	videoListOptions,
} from "@flux/shared";
import {
	keepPreviousData,
	useInfiniteQuery,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import { normalizeSearchQuery, type SortOrder } from "../media/search";

// CoreFetcher уже платформенно-нейтрален; транспорт подставляет
// configureApi (Bearer + базовый URL сервера).
const fetcher: CoreFetcher = (path, init) => apiFetch(path, init);

// Нормализация и query key живут в shared: смена q/sort автоматически
// сбрасывает пагинацию (новый infinite-запрос с offset=0).
export function videoSearchOptions(
	fetch: CoreFetcher,
	q: string,
	sort: SortOrder,
) {
	return {
		...videoListOptions(fetch, normalizeSearchQuery(q), sort),
		// Смена q/sort не должна схлопывать уже загруженный список в
		// спиннер: предыдущие данные остаются до ответа нового ключа.
		placeholderData: keepPreviousData,
	};
}

export function audioSearchOptions(
	fetch: CoreFetcher,
	q: string,
	sort: SortOrder,
) {
	// artistId не передаём: отдельный список артиста — useArtistTracks.
	return {
		...audioListOptions(fetch, normalizeSearchQuery(q), undefined, sort),
		placeholderData: keepPreviousData,
	};
}

export function useVideoList(q = "", sort: SortOrder = "desc") {
	return useInfiniteQuery(videoSearchOptions(fetcher, q, sort));
}

export function useAudioList(q = "", sort: SortOrder = "desc") {
	return useInfiniteQuery(audioSearchOptions(fetcher, q, sort));
}

export function useImageList(q = "") {
	return useInfiniteQuery(imageListOptions(fetcher, normalizeSearchQuery(q)));
}

// Треки артиста фильтруются на сервере (artist_id): клиент не тянет всю
// аудиотеку и не фильтрует её в памяти. enabled — для невалидного id.
export function useArtistTracks(artistId: number, enabled = true) {
	return useInfiniteQuery({
		...audioListOptions(fetcher, "", artistId),
		enabled,
	});
}

// Детали медиа: enabled выключает запрос для невалидного id из маршрута,
// чтобы экран показал 404, а не запрашивал /media/0.
export function useMedia(id: number, enabled = true) {
	return useQuery({ ...mediaOptions(fetcher, id), enabled });
}

// Удаление в корзину (только админ). Инвалидация как в web: списки,
// корзина и коллекции — удалённая запись не должна оставаться в кэше.
export function useDeleteMedia() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (mediaId: number) =>
			apiFetch<unknown>(`/media/${mediaId}`, { method: "DELETE" }),
		onSuccess: () => {
			void queryClient.invalidateQueries({ queryKey: ["media"] });
			void queryClient.invalidateQueries({ queryKey: ["trash"] });
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
			void queryClient.invalidateQueries({ queryKey: ["favorites"] });
			void queryClient.invalidateQueries({ queryKey: ["progress"] });
			void queryClient.invalidateQueries({ queryKey: ["lyrics"] });
		},
	});
}

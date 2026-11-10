import {
	apiFetch,
	audioListOptions,
	type CoreFetcher,
	mediaOptions,
	videoListOptions,
} from "@flux/shared";
import {
	useInfiniteQuery,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";

// CoreFetcher уже платформенно-нейтрален; транспорт подставляет
// configureApi (Bearer + базовый URL сервера).
const fetcher: CoreFetcher = (path, init) => apiFetch(path, init);

export function useVideoList() {
	return useInfiniteQuery(videoListOptions(fetcher, ""));
}

export function useAudioList() {
	return useInfiniteQuery(audioListOptions(fetcher, ""));
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
		},
	});
}

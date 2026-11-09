import {
	useInfiniteQuery,
	useMutation,
	useQuery,
	useQueryClient,
} from "@tanstack/react-query";
import type { RefObject } from "react";
import { useCallback, useRef, useState } from "react";
import {
	audioListOptions,
	imageListOptions,
	mediaOptions,
	mediaSubsOptions,
	videoListOptions,
} from "../core/media";
import { apiFetch } from "./client";
export function useVideoList(q: string) {
	return useInfiniteQuery(videoListOptions(apiFetch, q));
}

export function useAudioList(q: string, artistId?: number, enabled = true) {
	return useInfiniteQuery({
		...audioListOptions(apiFetch, q, artistId),
		enabled,
	});
}

export function useImageList(q: string) {
	return useInfiniteQuery(imageListOptions(apiFetch, q));
}

export function useMedia(id: number, enabled = true) {
	return useQuery({ ...mediaOptions(apiFetch, id), enabled });
}

export function useMediaSubs(mediaId: number, enabled = true) {
	return useQuery({ ...mediaSubsOptions(apiFetch, mediaId), enabled });
}

// Удаление медиа в корзину (только админ, как во Flutter — с
// подтверждением на экране). Инвалидация тройная, как у действий
// корзины: списки, сама корзина и коллекции.
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

// Повтор прямого медиа-запроса (<video>, <img>, <track>) после сбоя.
// onError не даёт HTTP-статус, поэтому сначала идёт зонд через apiFetch:
// при 401 зонд сам обновит сессию и повторит — успех значит «дело было
// в auth» и элемент перемонтируется (nonce для key). Неудача зонда
// (404/500/мертвая сессия) или повторная ошибка элемента — failed
// без дальнейших попыток и лишней ротации refresh-токена.
// retry() сбрасывает состояние и пробует снова.
export function useMediaReload(mediaId: number) {
	const [nonce, setNonce] = useState(0);
	const [failed, setFailed] = useState(false);
	const tried = useRef(false);
	const handleError = useCallback(() => {
		if (tried.current) {
			setFailed(true);
			return;
		}
		tried.current = true;
		void apiFetch(`/media/${mediaId}`).then(
			() => {
				setNonce((n) => n + 1);
			},
			() => {
				setFailed(true);
			},
		);
	}, [mediaId]);
	const retry = useCallback(() => {
		tried.current = false;
		setFailed(false);
		setNonce((n) => n + 1);
	}, []);
	return { nonce, failed, handleError, retry };
}

// Позиция воспроизведения переживает remount <video>/<audio key={nonce}>:
// save() — перед ЛЮБЫМ изменением nonce (ошибка элемента, ошибка track,
// кнопка retry), restore — напрямую в onLoadedMetadata (стабилен).
export function useSavedTime(ref: RefObject<HTMLMediaElement | null>) {
	const saved = useRef(0);
	const save = useCallback(() => {
		saved.current = ref.current?.currentTime ?? 0;
	}, [ref]);
	const restore = useCallback(() => {
		const el = ref.current;
		if (el !== null && saved.current > 0) {
			el.currentTime = saved.current;
			saved.current = 0;
		}
	}, [ref]);
	return { save, restore };
}

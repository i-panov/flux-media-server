// Общее ядро: модели, API-функции и форматирование, независимые от
// платформы. Границы (см. README.md в этой папке): только fetch, zod,
// TanStack Query и чистый TS — без DOM, роутера, Mantine и localStorage.
// При старте mobile/ папка целиком переезжает в packages/core.
import { infiniteQueryOptions, queryOptions } from "@tanstack/react-query";
import { z } from "zod";

// Транспорт подставляет приложение: веб — apiFetch (same-origin cookies),
// мобильное — абсолютный URL + Bearer. Ядро про транспорт ничего не знает.
export type CoreFetcher = (
	path: string,
	init?: { signal?: AbortSignal },
) => Promise<unknown>;

export const mediaSchema = z.object({
	id: z.number(),
	title: z.string(),
	year: z.number(),
	description: z.string(),
	// Бэкенд отдаёт "video" или "audio"; пустая строка возможна у старых
	// записей, поэтому фильтр «Продолжить просмотр» проверяет точное значение.
	type: z.string(),
	duration: z.number(),
	width: z.number(),
	height: z.number(),
	file_size: z.number(),
	thumbnail_url: z.string(),
	cover_url: z.string(),
	view_count: z.number(),
	created_at: z.string(),
});

export type Media = z.infer<typeof mediaSchema>;

const mediaListSchema = z.object({
	items: z.array(mediaSchema),
	total: z.number(),
	limit: z.number(),
	offset: z.number(),
});

export type MediaList = z.infer<typeof mediaListSchema>;

const VIDEO_PAGE_SIZE = 24;

const MEDIA_PATH = "/media";

interface VideoListRequest {
	q: string;
	limit: number;
	offset: number;
	signal?: AbortSignal;
}

export async function fetchVideoList(
	fetch: CoreFetcher,
	{ q, limit, offset, signal }: VideoListRequest,
): Promise<MediaList> {
	const params = new URLSearchParams({
		type: "video",
		limit: String(limit),
		offset: String(offset),
	});
	if (q !== "") {
		params.set("q", q);
	}
	const body = await fetch(`${MEDIA_PATH}?${params.toString()}`, { signal });
	return mediaListSchema.parse(body);
}

export function videoListOptions(fetch: CoreFetcher, q: string) {
	return infiniteQueryOptions({
		queryKey: ["media", "video", q],
		queryFn: ({ pageParam, signal }) =>
			fetchVideoList(fetch, {
				q,
				limit: VIDEO_PAGE_SIZE,
				offset: pageParam,
				signal,
			}),
		initialPageParam: 0,
		getNextPageParam: (lastPage, _allPages, lastOffset) => {
			// Пустая страница при total > offset (гонка с удалением):
			// тот же offset запросился бы снова — останавливаемся.
			if (lastPage.items.length === 0) {
				return;
			}
			const fetched = lastOffset + lastPage.items.length;
			return fetched < lastPage.total ? fetched : undefined;
		},
		retry: false,
		refetchOnWindowFocus: false,
	});
}

export async function fetchMediaById(
	fetch: CoreFetcher,
	id: number,
	signal?: AbortSignal,
): Promise<Media> {
	const body = await fetch(`${MEDIA_PATH}/${id}`, { signal });
	return mediaSchema.parse(body);
}

export function mediaOptions(fetch: CoreFetcher, id: number) {
	return queryOptions({
		queryKey: ["media", id],
		queryFn: ({ signal }) => fetchMediaById(fetch, id, signal),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

const subtitleSchema = z.object({
	lang: z.string(),
	url: z.string(),
});

export type Subtitle = z.infer<typeof subtitleSchema>;

export async function fetchMediaSubs(
	fetch: CoreFetcher,
	mediaId: number,
	signal?: AbortSignal,
): Promise<Subtitle[]> {
	const body = await fetch(`${MEDIA_PATH}/${mediaId}/subs`, { signal });
	return z.array(subtitleSchema).parse(body);
}

export function mediaSubsOptions(fetch: CoreFetcher, mediaId: number) {
	return queryOptions({
		queryKey: ["media", mediaId, "subs"],
		queryFn: ({ signal }) => fetchMediaSubs(fetch, mediaId, signal),
		retry: false,
		refetchOnWindowFocus: false,
	});
}

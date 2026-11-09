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

const artistSchema = z.object({
	id: z.number(),
	name: z.string(),
});

export const mediaSchema = z.object({
	id: z.number(),
	title: z.string(),
	// Имя файла с расширением: нужно для скачивания мема.
	filename: z.string().default(""),
	year: z.number(),
	description: z.string(),
	// Бэкенд отдаёт "video" или "audio"; пустая строка возможна у старых
	// записей, поэтому фильтр «Продолжить просмотр» проверяет точное значение.
	type: z.string(),
	// В прогрессии медиа приходит без artists (Preload без связей) — null.
	artists: z
		.array(artistSchema)
		.nullish()
		.transform((list) => list ?? []),
	album: z.string().default(""),
	genre: z.string().default(""),
	duration: z.number(),
	width: z.number(),
	height: z.number(),
	file_size: z.number(),
	thumbnail_url: z.string(),
	cover_url: z.string(),
	view_count: z.number(),
	created_at: z.string(),
	// Ссылка на источник: старые ответы и вложенные медиа (очередь,
	// избранное) её не содержат — default вместо optional.
	source_url: z.string().default(""),
});

export type Media = z.infer<typeof mediaSchema>;

const mediaListSchema = z.object({
	items: z.array(mediaSchema),
	total: z.number(),
	limit: z.number(),
	offset: z.number(),
});

export type MediaList = z.infer<typeof mediaListSchema>;

const MEDIA_PAGE_SIZE = 24;

const MEDIA_PATH = "/media";

export type MediaType = "video" | "audio" | "image";

// «Продолжить просмотр/прослушивание» — только медиа с прогрессом.
export type MediaKind = Exclude<MediaType, "image">;

const URL_SCHEME_PATTERN = /^([a-zA-Z][a-zA-Z0-9+.-]*):/;

// Обложка уходит в CSS backgroundImage: чужая схема (javascript:, data:,
// blob: и т.п.) вместо картинки дала бы пустой или мусорный фон.
// Разрешаем http(s) и относительные пути (без схемы), остальное —
// сигнал показать заглушку вместо фона.
export function isSafeImageUrl(url: string): boolean {
	if (url === "") {
		return false;
	}
	const scheme = URL_SCHEME_PATTERN.exec(url);
	if (scheme?.[1] === undefined) {
		return true;
	}
	const name = scheme[1].toLowerCase();
	return name === "http" || name === "https";
}

interface MediaListRequest {
	type: MediaType;
	q: string;
	limit: number;
	offset: number;
	sort?: "asc" | "desc";
	artistId?: number;
	signal?: AbortSignal;
}

export async function fetchMediaList(
	fetch: CoreFetcher,
	{ type, q, limit, offset, sort, artistId, signal }: MediaListRequest,
): Promise<MediaList> {
	const params = new URLSearchParams({
		type,
		limit: String(limit),
		offset: String(offset),
	});
	if (q !== "") {
		params.set("q", q);
	}
	if (sort !== undefined) {
		params.set("sort", sort);
	}
	if (artistId !== undefined) {
		params.set("artist_id", String(artistId));
	}
	const body = await fetch(`${MEDIA_PATH}?${params.toString()}`, { signal });
	return mediaListSchema.parse(body);
}

function mediaListOptions(
	fetch: CoreFetcher,
	type: MediaType,
	q: string,
	sort?: "asc" | "desc",
	artistId?: number,
) {
	return infiniteQueryOptions({
		queryKey: ["media", type, q, sort ?? "", artistId ?? 0],
		queryFn: ({ pageParam, signal }) =>
			fetchMediaList(fetch, {
				type,
				q,
				limit: MEDIA_PAGE_SIZE,
				offset: pageParam,
				sort,
				artistId,
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

// Видео и аудио — новые сверху: свежая загрузка должна быть на экране,
// а не в конце бесконечного списка. Мемы уже сортируются так же.
export function videoListOptions(fetch: CoreFetcher, q: string) {
	return mediaListOptions(fetch, "video", q, "desc");
}

export function audioListOptions(
	fetch: CoreFetcher,
	q: string,
	artistId?: number,
) {
	return mediaListOptions(fetch, "audio", q, "desc", artistId);
}

// Мемы — новые сверху: сервер сортирует по id DESC.
export function imageListOptions(fetch: CoreFetcher, q: string) {
	return mediaListOptions(fetch, "image", q, "desc");
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

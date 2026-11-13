import { z } from "zod";
import { type Media, type MediaType, mediaSchema } from "../core/media";
import { ApiError, apiFetch } from "./client";

export const favoriteSchema = z.object({
	id: z.number(),
	user_id: z.number(),
	media_id: z.number().nullish(),
	artist_id: z.number().nullish(),
	media: mediaSchema.nullish(),
	created_at: z.string(),
});

export type Favorite = z.infer<typeof favoriteSchema>;

export const favoritesListSchema = z.object({
	items: z.array(favoriteSchema),
	total: z.number(),
	limit: z.number(),
	offset: z.number(),
});

export type FavoritesList = z.infer<typeof favoritesListSchema>;

// Верхняя граница API — 200. Тянем все страницы один раз: секция
// «Избранное» показывает медиа, а сердечки получают тот же набор через
// select — без второго запроса за теми же данными.
const FAVORITES_LIMIT = 200;

function favoritesPageParams(
	type: MediaType | null,
	offset: number,
): URLSearchParams {
	const params = new URLSearchParams();
	if (type !== null) {
		params.set("type", type);
	}
	params.set("limit", String(FAVORITES_LIMIT));
	params.set("offset", String(offset));
	return params;
}

async function fetchFavoritePages(
	type: MediaType | null,
	handlePage: (page: FavoritesList) => void,
): Promise<void> {
	let offset = 0;
	// total фиксируем с первой страницы: счётчик на сервере может
	// расти между запросами — иначе догоняли бы его вечно.
	let firstTotal: number | null = null;
	do {
		const params = favoritesPageParams(type, offset);
		const body = await apiFetch<unknown>(`/favorites?${params.toString()}`);
		const page = favoritesListSchema.parse(body);
		if (firstTotal === null) {
			firstTotal = page.total;
		}
		handlePage(page);
		const fetched = page.items.length;
		if (fetched === 0) {
			break;
		}
		offset += fetched;
	} while (offset < (firstTotal ?? 0));
}

export async function fetchFavoriteMedia(type: MediaType): Promise<Media[]> {
	const media: Media[] = [];
	await fetchFavoritePages(type, (page) => {
		for (const entry of page.items) {
			if (entry.media !== null && entry.media !== undefined) {
				media.push(entry.media);
			}
		}
	});
	return media;
}

// Избранные артисты живут отдельно от медиа: в GET /favorites без фильтра
// по типу их строки (media_id NULL, artist_id задан) приходят вместе
// с медиа-избранным — забираем только id артистов.
export async function fetchFavoriteArtistIds(): Promise<Set<number>> {
	try {
		const body = await apiFetch<unknown>("/favorites/artists");
		const parsed = z.object({ items: z.array(z.number()) }).parse(body);
		return new Set(parsed.items);
	} catch (error) {
		// Старый backend без endpoint: прежний путь через все избранные.
		if (!(error instanceof ApiError) || error.status !== 404) {
			throw error;
		}
	}
	const ids = new Set<number>();
	await fetchFavoritePages(null, (page) => {
		for (const entry of page.items) {
			if (entry.artist_id !== null && entry.artist_id !== undefined) {
				ids.add(entry.artist_id);
			}
		}
	});
	return ids;
}

// 409 на POST — уже в избранном, 404 на DELETE — уже удалено в другой
// вкладке. Оба случая лечим инвалидацией, а не ошибкой пользователю.
export function isStaleFavoriteError(
	error: unknown,
	favorite: boolean,
): boolean {
	if (!(error instanceof ApiError)) {
		return false;
	}
	return (
		(!favorite && error.status === 409) || (favorite && error.status === 404)
	);
}

// favorite — текущее состояние: true означает «уже в избранном», то есть
// переключение удаляет запись.
export async function toggleFavorite(
	mediaId: number,
	favorite: boolean,
): Promise<void> {
	try {
		await apiFetch<unknown>(`/media/${mediaId}/favorite`, {
			method: favorite ? "DELETE" : "POST",
		});
	} catch (error) {
		if (isStaleFavoriteError(error, favorite)) {
			return;
		}
		throw error;
	}
}

export async function toggleArtistFavorite(
	artistId: number,
	favorite: boolean,
): Promise<void> {
	try {
		if (favorite) {
			await apiFetch<unknown>(`/favorites/artist?artist_id=${artistId}`, {
				method: "DELETE",
			});
		} else {
			await apiFetch<unknown>("/favorites/artist", {
				method: "POST",
				body: JSON.stringify({ artist_id: artistId }),
			});
		}
	} catch (error) {
		if (isStaleFavoriteError(error, favorite)) {
			return;
		}
		throw error;
	}
}

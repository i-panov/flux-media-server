import { apiFetch, type CoreFetcher } from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

// Справочник артистов живёт отдельно от медиа: GET /artists отдаёт только
// id/имя/обложку, а треки артиста запрашиваются через artist_id.
const fetcher: CoreFetcher = (path, init) => apiFetch(path, init);

export interface ArtistEntry {
	id: number;
	name: string;
	has_cover: boolean;
	updated_at: string;
}

export const artistsQueryKey = ["artists"] as const;

function parseArtistEntry(value: unknown): ArtistEntry | null {
	if (value === null || typeof value !== "object") {
		return null;
	}
	const record = value as Record<string, unknown>;
	if (
		typeof record.id !== "number" ||
		!Number.isSafeInteger(record.id) ||
		record.id <= 0 ||
		typeof record.name !== "string"
	) {
		return null;
	}
	return {
		id: record.id,
		name: record.name,
		has_cover: record.has_cover === true,
		updated_at: typeof record.updated_at === "string" ? record.updated_at : "",
	};
}

function artistItems(body: unknown): unknown[] {
	if (Array.isArray(body)) {
		return body;
	}
	if (body !== null && typeof body === "object") {
		const items = (body as { items?: unknown }).items;
		if (Array.isArray(items)) {
			return items;
		}
	}
	throw new Error("Unexpected artists response");
}

// Бэкенд может вернуть дубликаты имён (артист без нормализации) —
// список в UI должен оставаться уникальным и отсортированным, как в web.
export function normalizeArtists(body: unknown): ArtistEntry[] {
	const entries = artistItems(body).flatMap((item) => {
		const artist = parseArtistEntry(item);
		return artist === null || artist.name.trim() === "" ? [] : [artist];
	});
	const seen = new Set<string>();
	return entries
		.filter((artist) => {
			if (seen.has(artist.name)) {
				return false;
			}
			seen.add(artist.name);
			return true;
		})
		.sort((a, b) => a.name.localeCompare(b.name));
}

export async function fetchArtists(
	signal?: AbortSignal,
): Promise<ArtistEntry[]> {
	const body = await fetcher("/artists", { signal });
	return normalizeArtists(body);
}

export function useMediaArtists(enabled = true) {
	return useQuery({
		queryKey: artistsQueryKey,
		queryFn: ({ signal }) => fetchArtists(signal),
		retry: false,
		refetchOnWindowFocus: false,
		enabled,
	});
}

// GET /artists/:id на бэкенде нет: артист ищется в общем справочнике.
// enabled выключает запрос для невалидного id из deep link, чтобы экран
// показал 404 без обращения к сети.
export function useArtist(artistId: number, enabled = true) {
	const artists = useMediaArtists(enabled);
	const artist = enabled
		? artists.data?.find((item) => item.id === artistId)
		: undefined;
	return {
		artist,
		hasData: artists.data !== undefined,
		isPending: artists.isPending,
		isError: artists.isError,
		refetch: artists.refetch,
	};
}

export async function renameArtist(
	id: number,
	name: string,
): Promise<ArtistEntry> {
	const body = await apiFetch<unknown>(`/artists/${id}`, {
		method: "PUT",
		body: JSON.stringify({ name }),
	});
	const artist = parseArtistEntry(body);
	if (artist === null) {
		throw new Error("Unexpected artist response");
	}
	return artist;
}

export function useRenameArtist() {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: ({ id, name }: { id: number; name: string }) =>
			renameArtist(id, name),
		onSuccess: () => {
			// Имя артиста лежит в справочнике, в media.artists и в избранном
			// (там медиа с вложенными артистами): инвалидируем все три кэша.
			// Очередь и lock screen обновляет AudioProvider по artist_id.
			void queryClient.invalidateQueries({ queryKey: ["artists"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
			void queryClient.invalidateQueries({ queryKey: ["favorites"] });
		},
	});
}

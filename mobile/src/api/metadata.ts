import {
	apiFetch,
	type CoreFetcher,
	type Media,
	mediaSchema,
} from "@flux/shared";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

// Справочник артистов живёт отдельно от медиа: GET /artists отдаёт только
// id/имя/обложку, а треки артиста запрашиваются через artist_id.
const fetcher: CoreFetcher = (path, init) => apiFetch(path, init);

export interface MetadataInput {
	title: string;
	artists: string[];
	album?: string;
	genre?: string;
	year?: number;
	description?: string;
	sourceUrl?: string;
}

// Черновик редактора: все поля — строки, чтобы TextInput не терял ввод
// (пустой год и «0» различаются до валидации).
export interface MetadataDraft {
	title: string;
	artists: string[];
	album: string;
	genre: string;
	year: string;
	description: string;
	sourceUrl: string;
}

export interface MetadataValidation {
	title: boolean;
	year: boolean;
	sourceUrl: boolean;
}

export const MIN_METADATA_YEAR = 1888;
export const MAX_SOURCE_URL_LENGTH = 2048;
const MAX_YEAR_OFFSET = 2;
const YEAR_PATTERN = /^\d{4}$/;
const USERINFO_PATTERN = /^[a-z][a-z0-9+.-]*:\/\/[^/?#]*@/i;
const INVALID_PERCENT_PATTERN = /%(?![0-9A-Fa-f]{2})/;

export function metadataDraftFromMedia(media: Media): MetadataDraft {
	return {
		title: media.title,
		artists: media.artists.map((artist) => artist.name),
		album: media.album,
		genre: media.genre,
		year: media.year > 0 ? String(media.year) : "",
		description: media.description,
		sourceUrl: media.source_url,
	};
}

// Имена артистов — отдельные поля, поэтому запятая внутри имени
// ("Tyler, The Creator") не считается разделителем. Только trim, пустые
// значения и точные дубликаты: backend resolveArtists сам схлопывает
// регистр, а портить ввод пользователя редактор не должен.
export function normalizeArtistNames(names: readonly string[]): string[] {
	const seen = new Set<string>();
	const artists: string[] = [];
	for (const raw of names) {
		const name = raw.trim();
		if (name === "" || seen.has(name)) {
			continue;
		}
		seen.add(name);
		artists.push(name);
	}
	return artists;
}

// null — невалидный год. Пустая строка и «0» — осознанная очистка (0):
// backend принимает 0 как «год неизвестен».
export function parseYearInput(
	value: string,
	currentYear = new Date().getFullYear(),
): number | null {
	const trimmed = value.trim();
	if (trimmed === "" || trimmed === "0") {
		return 0;
	}
	if (!YEAR_PATTERN.test(trimmed)) {
		return null;
	}
	const year = Number(trimmed);
	if (year < MIN_METADATA_YEAR || year > currentYear + MAX_YEAR_OFFSET) {
		return null;
	}
	return year;
}

// Пустая ссылка валидна (очистка); непустая должна быть полным http(s)-URL.
// Повторяем ограничения backend.NormalizeSourceURL: длина, наличие хоста и
// запрет credentials (иначе 400 прилетел бы только после сохранения).
export function isValidSourceUrl(value: string): boolean {
	const trimmed = value.trim();
	if (trimmed === "") {
		return true;
	}
	if (trimmed.length > MAX_SOURCE_URL_LENGTH) {
		return false;
	}
	try {
		const url = new URL(trimmed);
		return (
			(url.protocol === "http:" || url.protocol === "https:") &&
			url.hostname !== "" &&
			// URL в JS отбрасывает пустой userinfo (http://@host), а backend
			// отклоняет любой userinfo — проверяем исходную authority.
			!USERINFO_PATTERN.test(trimmed) &&
			!INVALID_PERCENT_PATTERN.test(trimmed)
		);
	} catch {
		return false;
	}
}

export function validateMetadataDraft(
	draft: MetadataDraft,
	currentYear = new Date().getFullYear(),
): MetadataValidation {
	return {
		title: draft.title.trim() !== "",
		year: parseYearInput(draft.year, currentYear) !== null,
		sourceUrl: isValidSourceUrl(draft.sourceUrl),
	};
}

export function buildMetadataInput(draft: MetadataDraft): MetadataInput {
	return {
		title: draft.title.trim(),
		artists: normalizeArtistNames(draft.artists),
		album: draft.album.trim(),
		genre: draft.genre.trim(),
		// Валидацию делает validateMetadataDraft: сюда невалидный год
		// попасть не должен, поэтому null трактуется как очистка.
		year: parseYearInput(draft.year) ?? 0,
		description: draft.description.trim(),
		sourceUrl: draft.sourceUrl.trim(),
	};
}

function draftSignature(draft: MetadataDraft): string {
	return JSON.stringify([
		draft.title.trim(),
		normalizeArtistNames(draft.artists),
		draft.album.trim(),
		draft.genre.trim(),
		draft.year.trim(),
		draft.description.trim(),
		draft.sourceUrl.trim(),
	]);
}

export function isMetadataDraftDirty(
	initial: MetadataDraft,
	current: MetadataDraft,
): boolean {
	return draftSignature(initial) !== draftSignature(current);
}

// PUT с PATCH-семантикой: undefined — поле не трогать, пустая строка/0 —
// очистить. Редактор mobile всегда присылает все поля текущими значениями,
// поэтому очистка работает, а чужие поля остаются нетронутыми.
export async function updateMetadata(
	mediaId: number,
	input: MetadataInput,
): Promise<Media> {
	const body: Record<string, unknown> = {
		title: input.title,
		artists: input.artists,
	};
	if (input.album !== undefined) {
		body.album = input.album;
	}
	if (input.genre !== undefined) {
		body.genre = input.genre;
	}
	if (input.year !== undefined) {
		body.year = input.year;
	}
	if (input.description !== undefined) {
		body.description = input.description;
	}
	if (input.sourceUrl !== undefined) {
		body.source_url = input.sourceUrl;
	}
	const response = await apiFetch<unknown>(`/metadata/${mediaId}`, {
		method: "PUT",
		body: JSON.stringify(body),
	});
	return mediaSchema.parse(response);
}

export function useUpdateMetadata(mediaId: number) {
	const queryClient = useQueryClient();
	return useMutation({
		mutationFn: (input: MetadataInput) => updateMetadata(mediaId, input),
		onSuccess: (media) => {
			// Детали обновляются сразу, списки и подборки — после refetch:
			// название могли поменять в любом месте библиотеки. Артисты
			// могли создаться/исчезнуть, поэтому их справочник тоже
			// сбрасываем.
			queryClient.setQueryData(["media", media.id], media);
			void queryClient.invalidateQueries({ queryKey: ["media"] });
			void queryClient.invalidateQueries({ queryKey: ["artists"] });
			void queryClient.invalidateQueries({ queryKey: ["favorites"] });
			void queryClient.invalidateQueries({ queryKey: ["collections"] });
			void queryClient.invalidateQueries({ queryKey: ["progress"] });
		},
	});
}

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

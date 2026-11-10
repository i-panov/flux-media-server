const ARTIST_ID_PATTERN = /^\d+$/;

// id из маршрута: строго цифры (без пробелов, знаков, экспоненты и hex).
// Мусор/deep link с /artists/0 не должен уходить в запросы.
export function parseArtistIdParam(
	value: string | readonly string[] | undefined,
): number | null {
	const raw = Array.isArray(value) ? value[0] : value;
	if (raw === undefined || !ARTIST_ID_PATTERN.test(raw)) {
		return null;
	}
	const id = Number(raw);
	return Number.isSafeInteger(id) && id > 0 ? id : null;
}

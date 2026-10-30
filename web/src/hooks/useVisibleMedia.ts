import { useFavoriteMedia } from "../api/favorites";
import type { Media, MediaType } from "../core/media";

// Основной список без дублей секции избранного: при пустом поиске
// избранное уже показано отдельным рядом выше, при поиске секции
// скрыты и фильтр не нужен.
export function useVisibleMedia(
	type: MediaType,
	items: Media[],
	isSearching: boolean,
): Media[] {
	const favoriteMedia = useFavoriteMedia(type);
	if (isSearching) {
		return items;
	}
	const favoriteIds = new Set(favoriteMedia.map((media) => media.id));
	return items.filter((media) => !favoriteIds.has(media.id));
}

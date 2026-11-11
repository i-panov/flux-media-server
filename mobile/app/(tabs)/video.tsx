import type { Media } from "@flux/shared";
import { router } from "expo-router";
import { useMemo, useState } from "react";
import { StyleSheet, Text } from "react-native";
import { useFavoriteVideoIds } from "../../src/api/favorites";
import { useVideoList } from "../../src/api/media";
import { VideoHomeRows } from "../../src/components/HomeRows";
import { MediaList } from "../../src/components/MediaList";
import { MediaSearchBar } from "../../src/components/MediaSearchBar";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { normalizeSearchQuery, type SortOrder } from "../../src/media/search";
import { useDebouncedValue } from "../../src/media/useDebouncedValue";
import { useTheme } from "../../src/theme/ThemeProvider";

// Стабильный обработчик: FlatList не получает новую функцию на каждый
// рендер экрана (набор в поиске перерисовывает его часто).
function openVideo(item: Media): void {
	router.push(`/video/${item.id}`);
}

export default function VideoScreen() {
	useLanguage();
	const { colors } = useTheme();
	const [query, setQuery] = useState("");
	const [sort, setSort] = useState<SortOrder>("desc");
	const debouncedQuery = useDebouncedValue(query);
	// Raw-запрос учитывается сразу: пустое состояние «ничего не найдено»
	// не должно на 300 мс показывать «библиотека пуста». Данные при этом
	// запрашиваются только по debounced-значению.
	const searching = debouncedQuery !== "" || normalizeSearchQuery(query) !== "";
	const list = useVideoList(debouncedQuery, sort);
	const favorites = useFavoriteVideoIds();
	// Ряды остаются смонтированными и просто скрываются: сброс поиска не
	// создаёт заново их запросы.
	const header = useMemo(
		() => <VideoHomeRows hidden={searching} />,
		[searching],
	);
	return (
		<Screen>
			<Text style={[styles.title, { color: colors.text }]}>
				{t("video.title")}
			</Text>
			<MediaSearchBar
				value={query}
				onChangeText={setQuery}
				sort={sort}
				onSortChange={setSort}
				placeholder={t("video.search")}
				testID="video-search"
			/>
			<MediaList
				query={list}
				onPressItem={openVideo}
				// При поиске home-ряды получают hidden и рендерят null,
				// не размонтируясь; избранное в результатах не исключается.
				ListHeaderComponent={header}
				// Избранное исключается только когда оно показано отдельным
				// рядом; в результатах поиска оно должно находиться.
				excludedIds={searching ? undefined : favorites.data}
				searching={searching}
				emptyTitle={
					searching ? t("search.noResults") : t("search.libraryEmpty")
				}
				emptyDescription={
					searching
						? t("search.noResultsHint")
						: t("search.libraryEmptyVideoHint")
				}
				emptyTestID={searching ? "video-search-empty" : "video-empty"}
			/>
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
});

import type { Media } from "@flux/shared";
import { router } from "expo-router";
import { useCallback, useMemo, useState } from "react";
import { useFavoriteAudioIds } from "../../src/api/favorites";
import { useAudioList } from "../../src/api/media";
import { AudioHomeRows } from "../../src/components/HomeRows";
import { MediaList } from "../../src/components/MediaList";
import { MediaSearchBar } from "../../src/components/MediaSearchBar";
import { Screen } from "../../src/components/Screen";
import { SectionHeader } from "../../src/components/SectionHeader";
import { UploadAction } from "../../src/components/UploadAction";
import { t, useLanguage } from "../../src/i18n";
import { normalizeSearchQuery, type SortOrder } from "../../src/media/search";
import { useDebouncedValue } from "../../src/media/useDebouncedValue";
import { excludeMediaIds } from "../../src/media/visibleMedia";
import { useAudioActions } from "../../src/player/AudioProvider";

export default function AudioScreen() {
	useLanguage();
	const [query, setQuery] = useState("");
	const [sort, setSort] = useState<SortOrder>("desc");
	const debouncedQuery = useDebouncedValue(query);
	// Raw-значение нужно только для мгновенного выбора пустого состояния;
	// сам запрос уходит после debounce.
	const searching = debouncedQuery !== "" || normalizeSearchQuery(query) !== "";
	const list = useAudioList(debouncedQuery, sort);
	// Только stable actions-контекст: вкладка не перерисовывается каждые
	// 500 мс от currentTime мини-плеера.
	const { playQueue } = useAudioActions();
	const favorites = useFavoriteAudioIds();
	// Очередь стартует из уже загруженных страниц списка: пользователь
	// слышит порядок, который видит, а не весь каталог. При поиске
	// избранное не исключается — оно входит в результаты, поэтому индексы
	// очереди и видимого списка совпадают в обоих режимах.
	const items = useMemo(() => {
		const loaded = list.data?.pages.flatMap((page) => page.items) ?? [];
		return searching ? loaded : excludeMediaIds(loaded, favorites.data);
	}, [list.data, favorites.data, searching]);
	// Стабильный элемент home-рядов: ввод в поиске не должен перерисовывать
	// их до того, как debounce активирует фильтр. hidden оставляет ряды
	// смонтированными, чтобы сброс поиска не поднимал запросы заново.
	const header = useMemo(
		() => <AudioHomeRows hidden={searching} />,
		[searching],
	);

	const onPressItem = useCallback(
		(item: Media) => {
			const startIndex = items.findIndex(
				(candidate) => candidate.id === item.id,
			);
			playQueue(items, Math.max(startIndex, 0));
		},
		[items, playQueue],
	);

	return (
		<Screen>
			<SectionHeader
				title={t("audio.title")}
				titleStyle={{ fontSize: 24 }}
				actionLabel={t("artists.title")}
				onActionPress={() => router.push("/artists")}
				actionTestID="audio-open-artists"
				trailing={<UploadAction type="audio" />}
			/>
			<MediaSearchBar
				value={query}
				onChangeText={setQuery}
				sort={sort}
				onSortChange={setSort}
				placeholder={t("audio.search")}
				testID="audio-search"
			/>
			<MediaList
				query={list}
				ListHeaderComponent={header}
				excludedIds={searching ? undefined : favorites.data}
				searching={searching}
				emptyTitle={
					searching ? t("search.noResults") : t("search.libraryEmpty")
				}
				emptyDescription={
					searching
						? t("search.noResultsHint")
						: t("search.libraryEmptyAudioHint")
				}
				emptyTestID={searching ? "audio-search-empty" : "audio-empty"}
				onPressItem={onPressItem}
			/>
		</Screen>
	);
}

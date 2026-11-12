import type { Media } from "@flux/shared";
import { router } from "expo-router";
import { useMemo, useState } from "react";
import { StyleSheet } from "react-native";
import {
	useFavoriteVideoIds,
	useToggleVideoFavorite,
} from "../../src/api/favorites";
import { useVideoList } from "../../src/api/media";
import { VideoHomeRows } from "../../src/components/HomeRows";
import { MediaActionsSheet } from "../../src/components/MediaActionsSheet";
import { MediaCard } from "../../src/components/MediaCard";
import { MediaGrid } from "../../src/components/MediaGrid";
import { MediaSearchBar } from "../../src/components/MediaSearchBar";
import { Screen } from "../../src/components/Screen";
import { SectionHeader } from "../../src/components/SectionHeader";
import { UploadAction } from "../../src/components/UploadAction";
import { useDownloadIndicator } from "../../src/downloads/DownloadProvider";
import { t, useLanguage } from "../../src/i18n";
import { normalizeSearchQuery, type SortOrder } from "../../src/media/search";
import { coverPath, thumbPath } from "../../src/media/source";
import { useAuthImageSource } from "../../src/media/useAuthImageSource";
import { useDebouncedValue } from "../../src/media/useDebouncedValue";
import { excludeMediaIds } from "../../src/media/visibleMedia";
import { isTV } from "../../src/tv/profile";
import { TVVideoList } from "../../src/tv/TVVideoList";

function VideoGridCard({
	media,
	onMenu,
}: {
	media: Media;
	onMenu: () => void;
}) {
	const favorites = useFavoriteVideoIds();
	const toggleFavorite = useToggleVideoFavorite();
	const download = useDownloadIndicator(media.id);
	const imageSource = useAuthImageSource(
		media.cover_url === ""
			? media.thumbnail_url === ""
				? null
				: thumbPath(media.id)
			: coverPath(media.id),
	);
	return (
		<MediaCard
			title={media.title}
			duration={media.duration}
			imageSource={imageSource}
			isFavorite={favorites.data?.has(media.id) ?? false}
			download={download ?? undefined}
			onPress={() => openVideo(media)}
			onFavoritePress={() =>
				toggleFavorite.mutate({
					mediaId: media.id,
					favorite: favorites.data?.has(media.id) ?? false,
					media,
				})
			}
			onMenuPress={onMenu}
			testID={`video-card-${media.id}`}
		/>
	);
}

// Стабильный обработчик: FlatList не получает новую функцию на каждый
// рендер экрана (набор в поиске перерисовывает его часто).
function openVideo(item: Media): void {
	router.push(`/video/${item.id}`);
}

export default function VideoScreen() {
	useLanguage();
	const [query, setQuery] = useState("");
	const [sort, setSort] = useState<SortOrder>("desc");
	const debouncedQuery = useDebouncedValue(query);
	// Raw-запрос учитывается сразу: пустое состояние «ничего не найдено»
	// не должно на 300 мс показывать «библиотека пуста». Данные при этом
	// запрашиваются только по debounced-значению.
	const searching = debouncedQuery !== "" || normalizeSearchQuery(query) !== "";
	const list = useVideoList(debouncedQuery, sort);
	const favorites = useFavoriteVideoIds();
	const [actionsMedia, setActionsMedia] = useState<Media | null>(null);
	const allItems = list.data?.pages.flatMap((page) => page.items) ?? [];
	const tvItems = excludeMediaIds(allItems, favorites.data);
	// Ряды остаются смонтированными и просто скрываются: сброс поиска не
	// создаёт заново их запросы.
	const header = useMemo(
		() => <VideoHomeRows hidden={searching} />,
		[searching],
	);
	return (
		<Screen>
			<SectionHeader
				title={t("video.title")}
				titleStyle={styles.title}
				trailing={<UploadAction type="video" />}
			/>
			<MediaSearchBar
				value={query}
				onChangeText={setQuery}
				sort={sort}
				onSortChange={setSort}
				placeholder={t("video.search")}
				testID="video-search"
			/>
			{isTV ? (
				<TVVideoList items={tvItems} onPressItem={openVideo} />
			) : (
				<MediaGrid
					items={
						searching ? allItems : excludeMediaIds(allItems, favorites.data)
					}
					renderCard={(item) => (
						<VideoGridCard media={item} onMenu={() => setActionsMedia(item)} />
					)}
					ListHeaderComponent={header}
					isPending={list.isPending}
					isError={list.isError && allItems.length === 0}
					isFetchingNextPage={list.isFetchingNextPage}
					onRetry={() => void list.refetch()}
					onEndReached={() => {
						if (list.hasNextPage && !list.isFetchingNextPage) {
							void list.fetchNextPage();
						}
					}}
					emptyTitle={
						searching ? t("search.noResults") : t("search.libraryEmpty")
					}
					emptyDescription={
						searching
							? t("search.noResultsHint")
							: t("search.libraryEmptyVideoHint")
					}
					testID="video-grid"
				/>
			)}
			<MediaActionsSheet
				media={actionsMedia}
				onClose={() => setActionsMedia(null)}
			/>
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
});

import type { Media } from "@flux/shared";
import { router } from "expo-router";
import { useMemo, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import {
	useFavoriteVideoIds,
	useToggleVideoFavorite,
} from "../../src/api/favorites";
import { useVideoList } from "../../src/api/media";
import { useSession } from "../../src/auth/session";
import { FranchisesList } from "../../src/catalog/FranchisesList";
import { WorksList } from "../../src/catalog/WorksList";
import { BulkTagsSheet } from "../../src/components/BulkTagsSheet";
import { VideoHomeRows } from "../../src/components/HomeRows";
import { MediaActionsSheet } from "../../src/components/MediaActionsSheet";
import { MediaCard } from "../../src/components/MediaCard";
import { MediaGrid } from "../../src/components/MediaGrid";
import { MediaSearchBar } from "../../src/components/MediaSearchBar";
import { Screen } from "../../src/components/Screen";
import { SectionHeader } from "../../src/components/SectionHeader";
import { TagFilterBar } from "../../src/components/TagFilterBar";
import { UploadAction } from "../../src/components/UploadAction";
import { type VideoTab, VideoTabs } from "../../src/components/VideoTabs";
import { useDownloadIndicator } from "../../src/downloads/DownloadProvider";
import { t, useLanguage } from "../../src/i18n";
import { normalizeSearchQuery, type SortOrder } from "../../src/media/search";
import { coverPath, thumbPath } from "../../src/media/source";
import { useAuthImageSource } from "../../src/media/useAuthImageSource";
import { useDebouncedValue } from "../../src/media/useDebouncedValue";
import { excludeMediaIds } from "../../src/media/visibleMedia";
import { useTheme } from "../../src/theme/ThemeProvider";
import { isTV } from "../../src/tv/profile";
import { TVVideoList } from "../../src/tv/TVVideoList";

function VideoGridCard({
	media,
	onMenu,
	selectable,
	selected,
	allowSelect,
	onSelect,
}: {
	media: Media;
	onMenu: () => void;
	selectable: boolean;
	selected: boolean;
	allowSelect: boolean;
	onSelect: () => void;
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
			imageCachePolicy={media.cover_url === "" ? "memory-disk" : "none"}
			isFavorite={favorites.data?.has(media.id) ?? false}
			download={download ?? undefined}
			onPress={() => (selectable ? onSelect() : openVideo(media))}
			onLongPress={allowSelect ? onSelect : undefined}
			selected={selected}
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

function SelectionBar({
	count,
	onTags,
	onCancel,
}: {
	count: number;
	onTags: () => void;
	onCancel: () => void;
}) {
	const { colors, spacing } = useTheme();
	return (
		<View style={[styles.selectionBar, { borderColor: colors.borderStrong }]}>
			<Text style={{ color: colors.text }}>
				{t("bulk.selected", { count })}
			</Text>
			<View style={[styles.selectionActions, { gap: spacing.sm }]}>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("bulk.tags")}
					hitSlop={8}
					style={styles.selectionButton}
					testID="bulk-tags-open"
					onPress={onTags}
				>
					<Text style={{ color: colors.accent }}>{t("bulk.tags")}</Text>
				</Pressable>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.cancel")}
					hitSlop={8}
					style={styles.selectionButton}
					testID="bulk-tags-cancel"
					onPress={onCancel}
				>
					<Text style={{ color: colors.textMuted }}>{t("common.cancel")}</Text>
				</Pressable>
			</View>
		</View>
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
	const [tab, setTab] = useState<VideoTab>("videos");
	const [formatID, setFormatID] = useState<number | null>(null);
	const [genreIDs, setGenreIDs] = useState<number[]>([]);
	const debouncedQuery = useDebouncedValue(query);
	const isGrid = tab === "videos" || tab === "films";
	// Raw-запрос учитывается сразу: пустое состояние «ничего не найдено»
	// не должно на 300 мс показывать «библиотека пуста». Данные при этом
	// запрашиваются только по debounced-значению.
	const searching = debouncedQuery !== "" || normalizeSearchQuery(query) !== "";
	const list = useVideoList(
		debouncedQuery,
		sort,
		{
			format: tab === "films" ? "film" : undefined,
			excludeFormat: tab === "videos" ? "film" : undefined,
			formatTagID: formatID === null ? undefined : formatID,
			tagIDs: genreIDs,
		},
		isGrid,
	);
	const favorites = useFavoriteVideoIds();
	const [actionsMedia, setActionsMedia] = useState<Media | null>(null);
	const session = useSession();
	const canBulkTag = session.data?.is_admin === true;
	const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
	const [bulkOpen, setBulkOpen] = useState(false);
	const selectionMode = selectedIds.size > 0;
	const toggleSelected = (id: number) => {
		setSelectedIds((prev) => {
			const next = new Set(prev);
			if (next.has(id)) {
				next.delete(id);
			} else {
				next.add(id);
			}
			return next;
		});
	};
	const allItems = list.data?.pages.flatMap((page) => page.items) ?? [];
	const tvItems = searching
		? allItems
		: excludeMediaIds(allItems, favorites.data);
	// Ряды остаются смонтированными и просто скрываются: сброс поиска не
	// создаёт заново их запросы.
	const header = useMemo(
		() => <VideoHomeRows hidden={searching || tab !== "videos"} />,
		[searching, tab],
	);
	return (
		<Screen>
			<SectionHeader
				title={t("video.title")}
				titleStyle={styles.title}
				trailing={isGrid ? <UploadAction type="video" /> : undefined}
			/>
			{selectionMode && (
				<SelectionBar
					count={selectedIds.size}
					onTags={() => setBulkOpen(true)}
					onCancel={() => setSelectedIds(new Set())}
				/>
			)}
			<VideoTabs
				value={tab}
				onChange={(next) => {
					if (next === tab) return;
					setTab(next);
					// Формат со старой вкладки может быть скрыт на новой.
					setFormatID(null);
					setSelectedIds(new Set());
				}}
			/>
			{!isGrid && (
				<TagFilterBar
					formatID={null}
					genreIDs={genreIDs}
					onFormatChange={() => undefined}
					onGenresChange={setGenreIDs}
					genresOnly
				/>
			)}
			{isGrid ? (
				<>
					<MediaSearchBar
						value={query}
						onChangeText={(value) => {
							setQuery(value);
							setSelectedIds(new Set());
						}}
						sort={sort}
						onSortChange={setSort}
						placeholder={t("video.search")}
						testID="video-search"
					/>
					<TagFilterBar
						formatID={formatID}
						genreIDs={genreIDs}
						onFormatChange={(value) => {
							setFormatID(value);
							setSelectedIds(new Set());
						}}
						onGenresChange={(value) => {
							setGenreIDs(value);
							setSelectedIds(new Set());
						}}
						hiddenFormatSlugs={tab === "videos" ? ["film"] : []}
					/>
					{isTV ? (
						<TVVideoList
							items={tvItems}
							onPressItem={openVideo}
							onEndReached={() => {
								if (list.hasNextPage && !list.isFetchingNextPage) {
									void list.fetchNextPage();
								}
							}}
							isPending={list.isPending}
							isError={list.isError && allItems.length === 0}
							isFetchingNextPage={list.isFetchingNextPage}
							onRetry={() => void list.refetch()}
						/>
					) : (
						<MediaGrid
							items={
								searching ? allItems : excludeMediaIds(allItems, favorites.data)
							}
							renderCard={(item) => (
								<VideoGridCard
									media={item}
									onMenu={() => setActionsMedia(item)}
									selectable={canBulkTag && selectionMode}
									selected={selectedIds.has(item.id)}
									allowSelect={canBulkTag}
									onSelect={() => toggleSelected(item.id)}
								/>
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
				</>
			) : tab === "franchises" ? (
				<FranchisesList tagIDs={genreIDs} />
			) : (
				<WorksList kind={tab} tagIDs={genreIDs} />
			)}
			<MediaActionsSheet
				media={actionsMedia}
				onClose={() => setActionsMedia(null)}
			/>
			{bulkOpen && (
				<BulkTagsSheet
					mediaIDs={[...selectedIds]}
					onClose={() => {
						setBulkOpen(false);
						setSelectedIds(new Set());
					}}
				/>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
	selectionBar: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		borderWidth: 1,
		borderRadius: 8,
		paddingHorizontal: 12,
		paddingVertical: 8,
	},
	selectionActions: { flexDirection: "row", alignItems: "center" },
	selectionButton: { minHeight: 44, justifyContent: "center" },
});

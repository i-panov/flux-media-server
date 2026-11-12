import type { Media } from "@flux/shared";
import { Redirect, router } from "expo-router";
import { useMemo, useState } from "react";
import { ActivityIndicator, FlatList, StyleSheet, View } from "react-native";
import { useImageList } from "../../src/api/media";
import { EmptyState } from "../../src/components/EmptyState";
import { ListFooter } from "../../src/components/ListFooter";
import { MediaActionsSheet } from "../../src/components/MediaActionsSheet";
import { MediaCard } from "../../src/components/MediaCard";
import { MediaSearchBar } from "../../src/components/MediaSearchBar";
import { Screen } from "../../src/components/Screen";
import { SectionHeader } from "../../src/components/SectionHeader";
import { UploadAction } from "../../src/components/UploadAction";
import { t, useLanguage } from "../../src/i18n";
import { thumbPath } from "../../src/media/source";
import { useAuthImageSource } from "../../src/media/useAuthImageSource";
import { useDebouncedValue } from "../../src/media/useDebouncedValue";
import { useTheme } from "../../src/theme/ThemeProvider";
import { isTV } from "../../src/tv/profile";

const NUMERIC_TITLE = /^\d+$/;

function MemeTile({ media, onMenu }: { media: Media; onMenu: () => void }) {
	const source = useAuthImageSource(
		media.thumbnail_url === "" ? null : thumbPath(media.id),
	);
	const title = NUMERIC_TITLE.test(media.title.trim()) ? "" : media.title;
	return (
		<View style={styles.cell}>
			<MediaCard
				title={title}
				imageSource={source}
				aspectRatio={1}
				variant="video"
				onPress={() => router.push(`/meme/${media.id}`)}
				onMenuPress={onMenu}
				testID={`meme-card-${media.id}`}
			/>
		</View>
	);
}

function MemesContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const [query, setQuery] = useState("");
	const debounced = useDebouncedValue(query);
	const list = useImageList(debounced);
	const items = useMemo(
		() => list.data?.pages.flatMap((page) => page.items) ?? [],
		[list.data],
	);
	const [actionsMedia, setActionsMedia] = useState<Media | null>(null);

	return (
		<Screen>
			<SectionHeader
				title={t("memes.title")}
				titleStyle={styles.title}
				trailing={<UploadAction type="image" />}
			/>
			<MediaSearchBar
				value={query}
				onChangeText={setQuery}
				placeholder={t("memes.search")}
				testID="memes-search"
			/>
			{list.isPending ? (
				<View style={styles.center}>
					<ActivityIndicator color={colors.accent} />
				</View>
			) : list.isError && list.data === undefined ? (
				<EmptyState
					icon="images-outline"
					title={t("memes.loadError")}
					description={t("memes.loadErrorHint")}
					actionLabel={t("common.retry")}
					onActionPress={() => void list.refetch()}
					testID="memes-error"
				/>
			) : (
				<FlatList
					data={items}
					keyExtractor={(item) => String(item.id)}
					numColumns={2}
					columnWrapperStyle={{ gap: spacing.md }}
					contentContainerStyle={{ gap: spacing.md, paddingBottom: spacing.xl }}
					ListEmptyComponent={
						<EmptyState
							icon="images-outline"
							title={t("memes.empty")}
							description={t("memes.emptyHint")}
							testID="memes-empty"
						/>
					}
					ListFooterComponent={
						<ListFooter
							isFetchingNextPage={list.isFetchingNextPage}
							isError={list.isError}
							onRetry={() => void list.refetch()}
						/>
					}
					onEndReached={() => {
						if (list.hasNextPage && !list.isFetchingNextPage) {
							void list.fetchNextPage();
						}
					}}
					onEndReachedThreshold={0.4}
					renderItem={({ item }) => (
						<MemeTile media={item} onMenu={() => setActionsMedia(item)} />
					)}
					testID="memes-list"
				/>
			)}
			<MediaActionsSheet
				media={actionsMedia}
				onClose={() => setActionsMedia(null)}
			/>
		</Screen>
	);
}

export default function MemesScreen() {
	return isTV ? <Redirect href="/video" /> : <MemesContent />;
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
	cell: { flex: 1 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
});

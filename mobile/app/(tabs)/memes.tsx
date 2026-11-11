import type { Media } from "@flux/shared";
import { router } from "expo-router";
import { useMemo, useState } from "react";
import {
	ActivityIndicator,
	FlatList,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useImageList } from "../../src/api/media";
import { EmptyState } from "../../src/components/EmptyState";
import { ListFooter } from "../../src/components/ListFooter";
import { MediaCard } from "../../src/components/MediaCard";
import { MediaSearchBar } from "../../src/components/MediaSearchBar";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { thumbPath } from "../../src/media/source";
import { useAuthImageSource } from "../../src/media/useAuthImageSource";
import { useDebouncedValue } from "../../src/media/useDebouncedValue";
import { useTheme } from "../../src/theme/ThemeProvider";

function MemeTile({ media }: { media: Media }) {
	const source = useAuthImageSource(thumbPath(media.id));
	return (
		<View style={styles.cell}>
			<MediaCard
				title={media.title}
				imageSource={source}
				aspectRatio={1}
				variant="video"
				onPress={() => router.push(`/meme/${media.id}`)}
				testID={`meme-card-${media.id}`}
			/>
		</View>
	);
}

export default function MemesScreen() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const [query, setQuery] = useState("");
	const debounced = useDebouncedValue(query);
	const list = useImageList(debounced);
	const items = useMemo(
		() => list.data?.pages.flatMap((page) => page.items) ?? [],
		[list.data],
	);

	return (
		<Screen>
			<Text style={[styles.title, { color: colors.text }]}>
				{t("memes.title")}
			</Text>
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
					renderItem={({ item }) => <MemeTile media={item} />}
					testID="memes-list"
				/>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
	cell: { flex: 1 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
});

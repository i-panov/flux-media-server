import type { MediaList as MediaListData } from "@flux/shared";
import { formatDuration } from "@flux/shared";
import type {
	InfiniteData,
	UseInfiniteQueryResult,
} from "@tanstack/react-query";
import {
	ActivityIndicator,
	FlatList,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { ListFooter } from "./ListFooter";

type MediaListQuery = UseInfiniteQueryResult<InfiniteData<MediaListData>>;

export function MediaList({ query }: { query: MediaListQuery }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const items = query.data?.pages.flatMap((page) => page.items) ?? [];

	if (query.isPending) {
		return (
			<View style={[styles.center, { gap: spacing.sm }]}>
				<ActivityIndicator color={colors.accent} />
				<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
			</View>
		);
	}
	if (query.isError && items.length === 0) {
		return <ErrorState onRetry={() => void query.refetch()} />;
	}
	return (
		<FlatList
			data={items}
			keyExtractor={(item) => String(item.id)}
			style={styles.fill}
			contentContainerStyle={
				items.length === 0 ? styles.emptyList : styles.list
			}
			ListEmptyComponent={<EmptyState title={t("media.empty")} />}
			onEndReached={() => {
				if (query.hasNextPage && !query.isFetchingNextPage) {
					void query.fetchNextPage();
				}
			}}
			onEndReachedThreshold={0.4}
			ListFooterComponent={
				<ListFooter
					isFetchingNextPage={query.isFetchingNextPage}
					isError={query.isError}
					onRetry={() => void query.refetch()}
				/>
			}
			renderItem={({ item }) => (
				<View
					style={[
						styles.row,
						{
							gap: spacing.md,
							padding: spacing.md,
							borderColor: colors.border,
							backgroundColor: colors.surface,
						},
					]}
				>
					<View style={styles.info}>
						<Text
							style={[styles.title, { color: colors.text }]}
							numberOfLines={2}
						>
							{item.title}
						</Text>
						<Text
							style={[styles.muted, { color: colors.textMuted }]}
							numberOfLines={1}
						>
							{item.artists.map((artist) => artist.name).join(", ")}
						</Text>
					</View>
					<Text style={[styles.muted, { color: colors.textMuted }]}>
						{formatDuration(item.duration)}
					</Text>
				</View>
			)}
		/>
	);
}

const styles = StyleSheet.create({
	fill: { flex: 1 },
	list: { gap: 8, paddingBottom: 24 },
	emptyList: { flexGrow: 1 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
	row: {
		flexDirection: "row",
		alignItems: "center",
		borderWidth: 1,
		borderRadius: 10,
	},
	info: { flex: 1 },
	title: { fontSize: 16, fontWeight: "600" },
	muted: { fontSize: 13 },
});

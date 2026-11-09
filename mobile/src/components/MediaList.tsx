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

type MediaListQuery = UseInfiniteQueryResult<InfiniteData<MediaListData>>;

export function MediaList({ query }: { query: MediaListQuery }) {
	useLanguage();
	const items = query.data?.pages.flatMap((page) => page.items) ?? [];
	if (query.isPending) {
		return (
			<View style={styles.center}>
				<ActivityIndicator />
				<Text>{t("common.loading")}</Text>
			</View>
		);
	}
	if (query.isError && items.length === 0) {
		return (
			<View style={styles.center}>
				<Text>{t("common.error")}</Text>
				<Text style={styles.link} onPress={() => void query.refetch()}>
					{t("common.retry")}
				</Text>
			</View>
		);
	}
	return (
		<FlatList
			data={items}
			keyExtractor={(item) => String(item.id)}
			contentContainerStyle={items.length === 0 ? styles.center : styles.list}
			ListEmptyComponent={<Text>{t("media.empty")}</Text>}
			onEndReached={() => {
				if (query.hasNextPage && !query.isFetchingNextPage) {
					void query.fetchNextPage();
				}
			}}
			onEndReachedThreshold={0.4}
			ListFooterComponent={
				query.isFetchingNextPage ? (
					<ActivityIndicator style={styles.footer} />
				) : query.isError ? (
					<Text style={styles.link} onPress={() => void query.refetch()}>
						{t("common.retry")}
					</Text>
				) : undefined
			}
			renderItem={({ item }) => (
				<View style={styles.row}>
					<View style={styles.info}>
						<Text style={styles.title} numberOfLines={2}>
							{item.title}
						</Text>
						<Text style={styles.muted} numberOfLines={1}>
							{item.artists.map((artist) => artist.name).join(", ")}
						</Text>
					</View>
					<Text style={styles.muted}>{formatDuration(item.duration)}</Text>
				</View>
			)}
		/>
	);
}

const styles = StyleSheet.create({
	list: { gap: 8, paddingBottom: 24 },
	center: { flex: 1, alignItems: "center", justifyContent: "center", gap: 8 },
	row: {
		flexDirection: "row",
		alignItems: "center",
		gap: 12,
		padding: 12,
		borderWidth: 1,
		borderColor: "#8884",
		borderRadius: 10,
	},
	info: { flex: 1 },
	title: { fontSize: 16, fontWeight: "600" },
	muted: { fontSize: 13, opacity: 0.6 },
	footer: { paddingVertical: 16 },
	link: { color: "#7048e8", fontWeight: "600" },
});

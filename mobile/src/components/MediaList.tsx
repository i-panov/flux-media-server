import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media, MediaList as MediaListData } from "@flux/shared";
import { formatDuration } from "@flux/shared";
import type {
	InfiniteData,
	UseInfiniteQueryResult,
} from "@tanstack/react-query";
import { type ReactElement, useEffect } from "react";
import {
	ActivityIndicator,
	FlatList,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useDownloadIndicator } from "../downloads/DownloadProvider";
import { t, useLanguage } from "../i18n";
import { excludeMediaIds } from "../media/visibleMedia";
import { useTheme } from "../theme/ThemeProvider";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { ListFooter } from "./ListFooter";

type MediaListQuery = UseInfiniteQueryResult<InfiniteData<MediaListData>>;

function RowDownloadIndicator({ mediaId }: { mediaId: number }) {
	const { colors } = useTheme();
	const indicator = useDownloadIndicator(mediaId);
	if (indicator === null) {
		return null;
	}
	return (
		<View
			testID={`media-row-${mediaId}-download-${indicator.status}`}
			accessibilityLabel={
				indicator.status === "downloaded"
					? t("downloads.downloaded")
					: indicator.status === "error"
						? t("downloads.errorUnknown")
						: t("downloads.downloading")
			}
			style={styles.download}
		>
			<Ionicons
				name={
					indicator.status === "downloaded"
						? "checkmark-circle"
						: indicator.status === "error"
							? "alert-circle-outline"
							: "arrow-down-circle-outline"
				}
				size={16}
				color={
					indicator.status === "error"
						? colors.danger
						: indicator.status === "downloaded"
							? colors.accent
							: colors.textMuted
				}
			/>
			{indicator.status === "downloading" && indicator.progress !== null && (
				<Text style={[styles.muted, { color: colors.textMuted }]}>
					{`${Math.round(indicator.progress * 100)}%`}
				</Text>
			)}
		</View>
	);
}

interface MediaListProps {
	query: MediaListQuery;
	/** Optional: без обработчика строка остаётся статичной (аудио-таб). */
	onPressItem?: (item: Media) => void;
	/** Локальные тексты пустого/ошибочного состояния (экран артиста). */
	emptyTitle?: string;
	emptyDescription?: string;
	emptyTestID?: string;
	errorTitle?: string;
	errorTestID?: string;
	testID?: string;
	/** Ряды главных над списком: скроллятся вместе с ним, а не отдельно. */
	ListHeaderComponent?: ReactElement;
	/** Избранное, уже показанное рядом выше. undefined — ещё не загружено. */
	excludedIds?: ReadonlySet<number>;
}

export function MediaList({
	query,
	onPressItem,
	emptyTitle,
	emptyDescription,
	emptyTestID,
	errorTitle,
	errorTestID,
	testID,
	ListHeaderComponent,
	excludedIds,
}: MediaListProps) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const allItems = query.data?.pages.flatMap((page) => page.items) ?? [];
	const items = excludeMediaIds(allItems, excludedIds);
	// Если первые страницы целиком состоят из избранного, догружаем
	// следующие, иначе основной список навсегда останется пустым.
	const waitingForMore =
		items.length === 0 && query.hasNextPage && !query.isError;
	const fetchNextPage = query.fetchNextPage;

	useEffect(() => {
		if (
			excludedIds === undefined ||
			!waitingForMore ||
			query.isFetchingNextPage
		) {
			return;
		}
		void fetchNextPage();
	}, [excludedIds, fetchNextPage, query.isFetchingNextPage, waitingForMore]);

	if (query.isPending) {
		return (
			<View style={[styles.center, { gap: spacing.sm }]}>
				<ActivityIndicator color={colors.accent} />
				<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
			</View>
		);
	}
	// data-first: ошибка рефетча не прячет уже загруженные страницы;
	// для пустого/частичного ответа retry остаётся в футере.
	if (query.isError && query.data === undefined) {
		return (
			<ErrorState
				title={errorTitle}
				onRetry={() => void query.refetch()}
				testID={errorTestID}
			/>
		);
	}
	return (
		<FlatList
			testID={testID}
			data={items}
			keyExtractor={(item) => String(item.id)}
			style={styles.fill}
			contentContainerStyle={
				items.length === 0 ? styles.emptyList : styles.list
			}
			ListHeaderComponent={ListHeaderComponent}
			ListEmptyComponent={
				waitingForMore ? (
					<View style={[styles.center, { gap: spacing.sm }]}>
						<ActivityIndicator color={colors.accent} />
						<Text style={{ color: colors.textMuted }}>
							{t("common.loading")}
						</Text>
					</View>
				) : (
					<EmptyState
						title={emptyTitle ?? t("media.empty")}
						description={emptyDescription}
						testID={emptyTestID}
					/>
				)
			}
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
				<Pressable
					accessibilityRole={onPressItem === undefined ? undefined : "button"}
					accessibilityLabel={
						onPressItem === undefined ? undefined : item.title
					}
					onPress={
						onPressItem === undefined ? undefined : () => onPressItem(item)
					}
					testID={
						onPressItem === undefined ? undefined : `media-row-${item.id}`
					}
					style={({ pressed }) => [
						styles.row,
						{
							gap: spacing.md,
							padding: spacing.md,
							borderColor: colors.border,
							backgroundColor: colors.surface,
						},
						pressed && onPressItem !== undefined && styles.pressed,
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
					<RowDownloadIndicator mediaId={item.id} />
					<Text style={[styles.muted, { color: colors.textMuted }]}>
						{formatDuration(item.duration)}
					</Text>
				</Pressable>
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
	download: { flexDirection: "row", alignItems: "center", gap: 2 },
	title: { fontSize: 16, fontWeight: "600" },
	muted: { fontSize: 13 },
	pressed: { opacity: 0.7 },
});

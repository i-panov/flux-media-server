import type { ReactElement } from "react";
import {
	ActivityIndicator,
	FlatList,
	type StyleProp,
	StyleSheet,
	Text,
	View,
	type ViewStyle,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { EmptyState } from "./EmptyState";
import { ErrorState } from "./ErrorState";
import { ListFooter } from "./ListFooter";
import {
	MediaCard,
	type MediaCardImageSource,
	type MediaCardVariant,
	type MediaDownloadState,
} from "./MediaCard";
import { resolveMediaGridState } from "./mediaGridState";

// Минимальная форма элемента сетки: Media из shared подходит структурно,
// а компонент не тащит зависимость от zod-схемы и легко тестируется.
export interface MediaGridItem {
	id: number | string;
	title: string;
	subtitle?: string;
	duration?: number;
	badge?: string;
	imageSource?: MediaCardImageSource;
	isFavorite?: boolean;
	variant?: MediaCardVariant;
	download?: MediaDownloadState;
}

export interface MediaGridProps<T extends MediaGridItem> {
	items: T[];
	onPressItem?: (item: T) => void;
	onLongPressItem?: (item: T) => void;
	onFavoriteItem?: (item: T) => void;
	onMenuItem?: (item: T) => void;
	onEndReached?: () => void;
	isPending?: boolean;
	isFetchingNextPage?: boolean;
	isError?: boolean;
	onRetry?: () => void;
	emptyTitle?: string;
	emptyDescription?: string;
	ListHeaderComponent?: ReactElement;
	contentContainerStyle?: StyleProp<ViewStyle>;
	testID?: string;
}

// Сетка карточек на FlatList: сама управляет прокруткой, поэтому её нельзя
// вкладывать в ScrollView — экран должен отдать ей flex-контейнер целиком.
export function MediaGrid<T extends MediaGridItem>({
	items,
	onPressItem,
	onLongPressItem,
	onFavoriteItem,
	onMenuItem,
	onEndReached,
	isPending = false,
	isFetchingNextPage = false,
	isError = false,
	onRetry,
	emptyTitle,
	emptyDescription,
	ListHeaderComponent,
	contentContainerStyle,
	testID,
}: MediaGridProps<T>) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const state = resolveMediaGridState({
		isPending,
		isError,
		itemCount: items.length,
	});
	const empty = state === "empty";

	if (state === "loading") {
		return (
			<View
				style={[styles.loading, { gap: spacing.sm }]}
				testID={
					testID === undefined ? "media-grid-loading" : `${testID}-loading`
				}
			>
				<ActivityIndicator color={colors.accent} />
				<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
			</View>
		);
	}

	if (state === "error") {
		return (
			<ErrorState
				onRetry={onRetry}
				testID={testID === undefined ? "media-grid-error" : `${testID}-error`}
			/>
		);
	}

	return (
		<FlatList
			data={items}
			keyExtractor={(item) => String(item.id)}
			numColumns={2}
			columnWrapperStyle={[styles.row, { marginBottom: spacing.md }]}
			contentContainerStyle={[
				{ paddingBottom: spacing.xl },
				empty && styles.emptyContent,
				contentContainerStyle,
			]}
			ListHeaderComponent={ListHeaderComponent}
			ListEmptyComponent={
				<EmptyState
					title={emptyTitle ?? t("media.empty")}
					description={emptyDescription}
				/>
			}
			ListFooterComponent={
				<ListFooter
					isFetchingNextPage={isFetchingNextPage}
					isError={isError}
					onRetry={onRetry}
				/>
			}
			onEndReached={onEndReached}
			onEndReachedThreshold={0.4}
			testID={testID}
			renderItem={({ item }) => (
				<View style={styles.cell}>
					<MediaCard
						title={item.title}
						subtitle={item.subtitle}
						duration={item.duration}
						badge={item.badge}
						variant={item.variant}
						imageSource={item.imageSource}
						isFavorite={item.isFavorite}
						download={item.download}
						onPress={
							onPressItem === undefined ? undefined : () => onPressItem(item)
						}
						onLongPress={
							onLongPressItem === undefined
								? undefined
								: () => onLongPressItem(item)
						}
						onFavoritePress={
							onFavoriteItem === undefined
								? undefined
								: () => onFavoriteItem(item)
						}
						onMenuPress={
							onMenuItem === undefined ? undefined : () => onMenuItem(item)
						}
						testID={testID === undefined ? undefined : `${testID}-${item.id}`}
					/>
				</View>
			)}
		/>
	);
}

const styles = StyleSheet.create({
	row: {
		justifyContent: "space-between",
	},
	cell: { width: "48%" },
	emptyContent: { flexGrow: 1 },
	loading: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
	},
});

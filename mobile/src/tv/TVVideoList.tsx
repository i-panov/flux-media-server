import { formatDuration, type Media } from "@flux/shared";
import {
	ActivityIndicator,
	FlatList,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { tvFocusStyle } from "./focus";

interface TVVideoListProps {
	items: readonly Media[];
	onPressItem: (media: Media) => void;
	onEndReached?: () => void;
	isPending?: boolean;
	isError?: boolean;
	isFetchingNextPage?: boolean;
	onRetry?: () => void;
	testID?: string;
}

// Список для 10-foot UI: крупные строки, минимум элементов, явный
// D-pad focus-ring. Обычный MediaList намеренно не используется:
// на TV он рендерил пустую область.
export function TVVideoList({
	items,
	onPressItem,
	onEndReached,
	isPending = false,
	isError = false,
	isFetchingNextPage = false,
	onRetry,
	testID = "tv-video-list",
}: TVVideoListProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();

	if (isPending && items.length === 0) {
		return (
			<View style={styles.empty} testID="tv-video-loading">
				<ActivityIndicator color={colors.accent} />
				<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
			</View>
		);
	}
	if (isError && items.length === 0) {
		return <ErrorState onRetry={onRetry} testID="tv-video-error" />;
	}
	if (items.length === 0) {
		return (
			<EmptyState
				title={t("media.empty")}
				description={t("search.libraryEmptyVideoHint")}
				testID="tv-video-empty"
			/>
		);
	}

	return (
		<FlatList
			style={styles.fill}
			data={items}
			keyExtractor={(item) => String(item.id)}
			ItemSeparatorComponent={() => <View style={{ height: spacing.sm }} />}
			contentContainerStyle={{ paddingBottom: spacing.xl }}
			testID={testID}
			onEndReached={onEndReached}
			onEndReachedThreshold={0.4}
			ListFooterComponent={
				isFetchingNextPage ? (
					<ActivityIndicator
						color={colors.accent}
						style={{ padding: spacing.lg }}
					/>
				) : undefined
			}
			renderItem={({ item, index }) => (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={item.title}
					hasTVPreferredFocus={index === 0}
					onPress={() => onPressItem(item)}
					testID={`tv-video-row-${item.id}`}
					style={({ focused, pressed }) => [
						styles.row,
						{
							backgroundColor: colors.surface,
							borderColor: colors.border,
							borderRadius: radii.md,
							padding: spacing.lg,
						},
						pressed && styles.pressed,
						tvFocusStyle(focused, colors.accent),
					]}
				>
					<View style={styles.info}>
						<Text
							style={[styles.title, { color: colors.text }]}
							numberOfLines={2}
						>
							{item.title}
						</Text>
						<Text style={{ color: colors.textMuted }} numberOfLines={1}>
							{item.artists.map((artist) => artist.name).join(", ") || "—"}
						</Text>
					</View>
					<Text style={[styles.duration, { color: colors.textMuted }]}>
						{formatDuration(item.duration)}
					</Text>
				</Pressable>
			)}
		/>
	);
}

const styles = StyleSheet.create({
	fill: { flex: 1 },
	row: {
		minHeight: 104,
		borderWidth: 1,
		flexDirection: "row",
		alignItems: "center",
		gap: 16,
	},
	info: { flex: 1, gap: 4 },
	title: { fontSize: 22, fontWeight: "700" },
	duration: { fontSize: 16 },
	empty: { flex: 1, alignItems: "center", justifyContent: "center", gap: 8 },
	pressed: { opacity: 0.75 },
});

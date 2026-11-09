import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface ListFooterProps {
	isFetchingNextPage?: boolean;
	isError?: boolean;
	onRetry?: () => void;
}

// Футер пагинации: спиннер следующей страницы или retry после ошибки.
// Рендерится внутри FlatList, поэтому не занимает место при обычном списке.
export function ListFooter({
	isFetchingNextPage = false,
	isError = false,
	onRetry,
}: ListFooterProps) {
	useLanguage();
	const { colors, spacing } = useTheme();

	if (!isFetchingNextPage && !isError) {
		return null;
	}

	return (
		<View
			style={[styles.container, { paddingVertical: spacing.lg }]}
			testID="list-footer"
		>
			{isFetchingNextPage && (
				<ActivityIndicator color={colors.accent} testID="list-footer-loading" />
			)}
			{isError && onRetry !== undefined && (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.retry")}
					onPress={onRetry}
					testID="list-footer-retry"
					hitSlop={8}
					style={styles.retryButton}
				>
					<Text style={[styles.link, { color: colors.accent }]}>
						{t("common.retry")}
					</Text>
				</Pressable>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	container: { alignItems: "center", gap: 8 },
	retryButton: {
		minHeight: 44,
		paddingHorizontal: 12,
		justifyContent: "center",
	},
	link: { fontSize: 14, fontWeight: "600" },
});

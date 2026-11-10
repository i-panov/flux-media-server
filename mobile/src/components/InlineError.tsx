import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface InlineErrorProps {
	message: string;
	onRetry?: () => void;
	testID?: string;
	retryTestID?: string;
}

// Ошибка фонового обновления при уже показанных данных: не подменяет
// экран целиком, а оставляет список/карточку и даёт повторить запрос.
export function InlineError({
	message,
	onRetry,
	testID,
	retryTestID,
}: InlineErrorProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();

	return (
		<View
			testID={testID}
			accessibilityRole="alert"
			style={[
				styles.container,
				{
					borderColor: colors.danger,
					borderRadius: radii.sm,
					paddingHorizontal: spacing.sm,
					paddingVertical: spacing.xs,
				},
			]}
		>
			<Text style={[styles.message, { color: colors.danger }]}>{message}</Text>
			{onRetry !== undefined && (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.retry")}
					onPress={onRetry}
					testID={retryTestID}
					hitSlop={4}
					style={styles.retry}
				>
					<Text style={[styles.retryLabel, { color: colors.accent }]}>
						{t("common.retry")}
					</Text>
				</Pressable>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	container: {
		flexDirection: "row",
		alignItems: "center",
		gap: 8,
		borderWidth: 1,
	},
	message: { flex: 1, fontSize: 13, lineHeight: 18 },
	retry: {
		minHeight: 44,
		minWidth: 44,
		paddingHorizontal: 8,
		alignItems: "center",
		justifyContent: "center",
	},
	retryLabel: { fontSize: 14, fontWeight: "600" },
});

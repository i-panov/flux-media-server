import Ionicons from "@expo/vector-icons/Ionicons";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface ErrorStateProps {
	title?: string;
	description?: string;
	onRetry?: () => void;
	retryLabel?: string;
	retryTestID?: string;
	testID?: string;
}

export function ErrorState({
	title,
	description,
	onRetry,
	retryLabel,
	retryTestID = "error-retry",
	testID = "error-state",
}: ErrorStateProps) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const label = retryLabel ?? t("common.retry");

	return (
		<View
			style={[styles.container, { gap: spacing.sm, padding: spacing.xl }]}
			testID={testID}
		>
			<View
				style={[styles.iconCircle, { backgroundColor: colors.surfaceMuted }]}
			>
				<Ionicons name="alert-circle-outline" size={30} color={colors.danger} />
			</View>
			<Text style={[styles.title, { color: colors.text }]}>
				{title ?? t("common.error")}
			</Text>
			{description !== undefined && (
				<Text style={[styles.description, { color: colors.textMuted }]}>
					{description}
				</Text>
			)}
			{onRetry !== undefined && (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={label}
					onPress={onRetry}
					testID={retryTestID}
					hitSlop={8}
					style={({ pressed }) => [
						styles.retry,
						{ borderColor: colors.accent },
						pressed && styles.pressed,
					]}
				>
					<Text style={[styles.retryLabel, { color: colors.accent }]}>
						{label}
					</Text>
				</Pressable>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	container: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
	},
	iconCircle: {
		width: 64,
		height: 64,
		borderRadius: 32,
		alignItems: "center",
		justifyContent: "center",
	},
	title: { fontSize: 17, fontWeight: "600", textAlign: "center" },
	description: { fontSize: 14, textAlign: "center", lineHeight: 20 },
	retry: {
		marginTop: 8,
		paddingHorizontal: 18,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
		borderRadius: 999,
		borderWidth: 1,
	},
	retryLabel: { fontSize: 14, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

import Ionicons from "@expo/vector-icons/Ionicons";
import type { ComponentProps } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useTheme } from "../theme/ThemeProvider";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

interface EmptyStateProps {
	title: string;
	description?: string;
	icon?: IoniconName;
	actionLabel?: string;
	onActionPress?: () => void;
	testID?: string;
}

export function EmptyState({
	title,
	description,
	icon = "file-tray-outline",
	actionLabel,
	onActionPress,
	testID = "empty-state",
}: EmptyStateProps) {
	const { colors, spacing } = useTheme();
	const showAction = actionLabel !== undefined && onActionPress !== undefined;

	return (
		<View
			style={[styles.container, { gap: spacing.sm, padding: spacing.xl }]}
			testID={testID}
		>
			<View
				style={[styles.iconCircle, { backgroundColor: colors.surfaceMuted }]}
			>
				<Ionicons name={icon} size={30} color={colors.textMuted} />
			</View>
			<Text style={[styles.title, { color: colors.text }]}>{title}</Text>
			{description !== undefined && (
				<Text style={[styles.description, { color: colors.textMuted }]}>
					{description}
				</Text>
			)}
			{showAction && (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={actionLabel}
					onPress={onActionPress}
					testID="empty-state-action"
					hitSlop={8}
					style={({ pressed }) => [
						styles.action,
						{ backgroundColor: colors.accent },
						pressed && styles.pressed,
					]}
				>
					<Text style={[styles.actionLabel, { color: colors.onAccent }]}>
						{actionLabel}
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
	action: {
		marginTop: 8,
		paddingHorizontal: 18,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
		borderRadius: 999,
	},
	actionLabel: { fontSize: 14, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

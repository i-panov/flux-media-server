import { Pressable, StyleSheet, Text, View } from "react-native";
import { useTheme } from "../theme/ThemeProvider";

interface SectionHeaderProps {
	title: string;
	subtitle?: string;
	actionLabel?: string;
	onActionPress?: () => void;
	actionTestID?: string;
	testID?: string;
}

export function SectionHeader({
	title,
	subtitle,
	actionLabel,
	onActionPress,
	actionTestID,
	testID,
}: SectionHeaderProps) {
	const { colors, spacing } = useTheme();
	const showAction = actionLabel !== undefined && onActionPress !== undefined;

	return (
		<View style={[styles.row, { gap: spacing.sm }]} testID={testID}>
			<View style={styles.info}>
				<Text style={[styles.title, { color: colors.text }]}>{title}</Text>
				{subtitle !== undefined && (
					<Text style={[styles.subtitle, { color: colors.textMuted }]}>
						{subtitle}
					</Text>
				)}
			</View>
			{showAction && (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={actionLabel}
					onPress={onActionPress}
					testID={actionTestID}
					hitSlop={8}
					style={({ pressed }) => [
						styles.action,
						{ backgroundColor: colors.surfaceMuted },
						pressed && styles.pressed,
					]}
				>
					<Text style={[styles.actionLabel, { color: colors.text }]}>
						{actionLabel}
					</Text>
				</Pressable>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	row: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
	},
	info: { flex: 1, gap: 2 },
	title: { fontSize: 18, fontWeight: "700" },
	subtitle: { fontSize: 13 },
	action: {
		paddingHorizontal: 12,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
		borderRadius: 999,
	},
	actionLabel: { fontSize: 13, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

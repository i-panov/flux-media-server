import Ionicons from "@expo/vector-icons/Ionicons";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface CollectionBulkBarProps {
	count: number;
	busy: boolean;
	onMove: () => void;
	onRemove: () => void;
	onClear: () => void;
}

// Нижняя панель выбранных элементов: счётчик и групповые действия.
// Держим её вне FlatList, чтобы кнопки не уезжали при прокрутке.
export function CollectionBulkBar({
	count,
	busy,
	onMove,
	onRemove,
	onClear,
}: CollectionBulkBarProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();

	return (
		<View
			testID="collection-bulk-bar"
			style={[
				styles.bar,
				{
					backgroundColor: colors.surface,
					borderColor: colors.border,
					borderRadius: radii.md,
					gap: spacing.xs,
					padding: spacing.sm,
				},
			]}
		>
			<Text style={[styles.count, { color: colors.text }]}>
				{t("collections.selected", { count })}
			</Text>
			<View style={[styles.actions, { gap: spacing.xs }]}>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("collections.moveSelected")}
					accessibilityState={{ disabled: busy }}
					disabled={busy}
					onPress={onMove}
					testID="collection-bulk-move"
					style={({ pressed }) => [
						styles.action,
						{ borderColor: colors.borderStrong, borderRadius: radii.sm },
						(pressed || busy) && styles.pressed,
					]}
				>
					<Ionicons name="arrow-redo-outline" size={16} color={colors.text} />
					<Text
						numberOfLines={1}
						style={[styles.actionLabel, { color: colors.text }]}
					>
						{t("collections.moveSelected")}
					</Text>
				</Pressable>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("collections.removeSelected")}
					accessibilityState={{ disabled: busy }}
					disabled={busy}
					onPress={onRemove}
					testID="collection-bulk-remove"
					style={({ pressed }) => [
						styles.action,
						{ borderColor: colors.danger, borderRadius: radii.sm },
						(pressed || busy) && styles.pressed,
					]}
				>
					<Ionicons name="trash-outline" size={16} color={colors.danger} />
					<Text
						numberOfLines={1}
						style={[styles.actionLabel, { color: colors.danger }]}
					>
						{t("collections.removeSelected")}
					</Text>
				</Pressable>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("collections.clearSelection")}
					onPress={onClear}
					testID="collection-bulk-clear"
					hitSlop={4}
					style={({ pressed }) => [styles.clear, pressed && styles.pressed]}
				>
					<Ionicons name="close" size={20} color={colors.textMuted} />
				</Pressable>
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	bar: { borderWidth: 1 },
	count: { fontSize: 13, fontWeight: "600" },
	actions: { flexDirection: "row", alignItems: "center" },
	action: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		flexShrink: 1,
		gap: 6,
		minHeight: 44,
		paddingHorizontal: 10,
		borderWidth: 1,
	},
	actionLabel: { flexShrink: 1, fontSize: 13, fontWeight: "600" },
	clear: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	pressed: { opacity: 0.7 },
});

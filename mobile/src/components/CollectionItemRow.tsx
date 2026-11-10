import Ionicons from "@expo/vector-icons/Ionicons";
import { formatDuration, type Media } from "@flux/shared";
import type { ComponentProps } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

function mediaIcon(type: string): IoniconName {
	if (type === "audio") {
		return "musical-notes-outline";
	}
	if (type === "image") {
		return "image-outline";
	}
	return "videocam-outline";
}

interface CollectionItemRowProps {
	item: Media;
	selecting: boolean;
	selected: boolean;
	onPress: () => void;
	onLongPress: () => void;
	onMove: () => void;
	onRemove: () => void;
}

// Строка элемента коллекции: в обычном режиме — переход/воспроизведение
// и точечные действия, в режиме выбора — чекбокс и переключение по тапу.
export function CollectionItemRow({
	item,
	selecting,
	selected,
	onPress,
	onLongPress,
	onMove,
	onRemove,
}: CollectionItemRowProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const artists = item.artists.map((artist) => artist.name).join(", ");

	return (
		<View
			style={[
				styles.row,
				{
					borderColor: selected ? colors.accent : colors.border,
					backgroundColor: colors.surface,
					borderRadius: radii.md,
					gap: spacing.sm,
					paddingLeft: spacing.sm,
					paddingRight: spacing.sm,
				},
			]}
		>
			{selecting && (
				<Ionicons
					name={selected ? "checkmark-circle" : "ellipse-outline"}
					size={22}
					color={selected ? colors.accent : colors.textMuted}
				/>
			)}
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={`${item.title}${artists === "" ? "" : `, ${artists}`}`}
				accessibilityState={{ selected }}
				onPress={onPress}
				onLongPress={onLongPress}
				delayLongPress={350}
				testID={`collection-item-${item.id}`}
				style={({ pressed }) => [styles.body, pressed && styles.pressed]}
			>
				<View
					style={[styles.iconCircle, { backgroundColor: colors.surfaceMuted }]}
				>
					<Ionicons
						name={mediaIcon(item.type)}
						size={18}
						color={colors.textMuted}
					/>
				</View>
				<View style={styles.info}>
					<Text
						numberOfLines={2}
						style={[styles.title, { color: colors.text }]}
					>
						{item.title}
					</Text>
					<View style={styles.metaRow}>
						{artists !== "" && (
							<Text
								numberOfLines={1}
								style={[styles.meta, { color: colors.textMuted }]}
							>
								{artists}
							</Text>
						)}
						<Text style={[styles.meta, { color: colors.textMuted }]}>
							{formatDuration(item.duration)}
						</Text>
					</View>
				</View>
			</Pressable>
			{!selecting && (
				<View style={styles.actions}>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("collections.moveItem")}
						onPress={onMove}
						testID={`collection-item-move-${item.id}`}
						hitSlop={4}
						style={({ pressed }) => [styles.action, pressed && styles.pressed]}
					>
						<Ionicons
							name="arrow-redo-outline"
							size={20}
							color={colors.textMuted}
						/>
					</Pressable>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("collections.removeItem")}
						onPress={onRemove}
						testID={`collection-item-remove-${item.id}`}
						hitSlop={4}
						style={({ pressed }) => [styles.action, pressed && styles.pressed]}
					>
						<Ionicons
							name="remove-circle-outline"
							size={20}
							color={colors.danger}
						/>
					</Pressable>
				</View>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	row: {
		flexDirection: "row",
		alignItems: "center",
		borderWidth: 1,
		minHeight: 64,
	},
	body: {
		flex: 1,
		flexDirection: "row",
		alignItems: "center",
		gap: 10,
		minHeight: 44,
		paddingVertical: 8,
	},
	iconCircle: {
		width: 32,
		height: 32,
		borderRadius: 16,
		alignItems: "center",
		justifyContent: "center",
	},
	info: { flex: 1, gap: 2 },
	title: { fontSize: 15, fontWeight: "600" },
	metaRow: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		gap: 8,
	},
	meta: { flexShrink: 1, fontSize: 12 },
	actions: { flexDirection: "row", alignItems: "center" },
	action: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	pressed: { opacity: 0.7 },
});

import { formatDuration, type Media } from "@flux/shared";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { tvFocusStyle } from "./focus";

interface TVVideoListProps {
	items: readonly Media[];
	onPressItem: (media: Media) => void;
	testID?: string;
}

// Список для 10-foot UI: крупные строки, минимум элементов, явный
// D-pad focus-ring. Обычный MediaList намеренно не используется:
// на TV он рендерил пустую область.
export function TVVideoList({
	items,
	onPressItem,
	testID = "tv-video-list",
}: TVVideoListProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();

	if (items.length === 0) {
		return (
			<View style={styles.empty}>
				<Text style={[styles.emptyTitle, { color: colors.text }]}>
					{t("media.empty")}
				</Text>
				<Text style={{ color: colors.textMuted }}>
					{t("search.libraryEmptyVideoHint")}
				</Text>
			</View>
		);
	}

	return (
		<ScrollView
			style={styles.fill}
			contentContainerStyle={{ gap: spacing.sm, paddingBottom: spacing.xl }}
			testID={testID}
		>
			{items.map((item, index) => (
				<Pressable
					key={item.id}
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
			))}
		</ScrollView>
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
	emptyTitle: { fontSize: 22, fontWeight: "700" },
	pressed: { opacity: 0.75 },
});

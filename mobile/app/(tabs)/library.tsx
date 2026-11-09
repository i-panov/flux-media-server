import { Pressable, StyleSheet, Text, View } from "react-native";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function LibraryScreen() {
	useLanguage();
	const { colors, spacing } = useTheme();
	// Маршрутов коллекций и избранного ещё нет: строки — заглушки,
	// которые станут ссылками в следующих задачах.
	return (
		<Screen testID="library-screen">
			<Text style={[styles.title, { color: colors.text }]}>
				{t("library.title")}
			</Text>
			<Text style={[styles.hint, { color: colors.textMuted }]}>
				{t("library.hint")}
			</Text>
			<View style={{ gap: spacing.sm, marginTop: spacing.sm }}>
				<Pressable
					disabled
					accessibilityRole="button"
					accessibilityState={{ disabled: true }}
					testID="library-collections"
					style={[
						styles.row,
						{
							padding: spacing.lg,
							borderColor: colors.border,
							backgroundColor: colors.surface,
						},
					]}
				>
					<Text style={[styles.rowTitle, { color: colors.text }]}>
						{t("library.collections")}
					</Text>
					<Text style={[styles.soon, { color: colors.textMuted }]}>
						{t("library.soon")}
					</Text>
				</Pressable>
				<Pressable
					disabled
					accessibilityRole="button"
					accessibilityState={{ disabled: true }}
					testID="library-favorites"
					style={[
						styles.row,
						{
							padding: spacing.lg,
							borderColor: colors.border,
							backgroundColor: colors.surface,
						},
					]}
				>
					<Text style={[styles.rowTitle, { color: colors.text }]}>
						{t("library.favorites")}
					</Text>
					<Text style={[styles.soon, { color: colors.textMuted }]}>
						{t("library.soon")}
					</Text>
				</Pressable>
			</View>
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
	hint: { fontSize: 14 },
	row: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		borderWidth: 1,
		borderRadius: 10,
	},
	rowTitle: { fontSize: 16, fontWeight: "600" },
	soon: { fontSize: 12 },
});

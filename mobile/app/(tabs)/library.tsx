import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function LibraryScreen() {
	useLanguage();
	const { colors, spacing } = useTheme();
	// Артисты — рабочий маршрут; коллекции и избранное пока заглушки,
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
					accessibilityRole="button"
					accessibilityLabel={t("artists.title")}
					onPress={() => router.push("/artists")}
					testID="library-artists"
					style={({ pressed }) => [
						styles.row,
						{
							padding: spacing.lg,
							borderColor: colors.border,
							backgroundColor: colors.surface,
						},
						pressed && styles.pressed,
					]}
				>
					<View style={styles.rowLead}>
						<Ionicons
							name="people-outline"
							size={20}
							color={colors.textMuted}
						/>
						<Text style={[styles.rowTitle, { color: colors.text }]}>
							{t("artists.title")}
						</Text>
					</View>
					<Ionicons name="chevron-forward" size={18} color={colors.textMuted} />
				</Pressable>
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
	rowLead: { flexDirection: "row", alignItems: "center", gap: 10 },
	rowTitle: { fontSize: 16, fontWeight: "600" },
	soon: { fontSize: 12 },
	pressed: { opacity: 0.7 },
});

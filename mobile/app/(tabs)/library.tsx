import { Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { t, useLanguage } from "../../src/i18n";

export default function LibraryScreen() {
	useLanguage();
	// Маршрутов коллекций и избранного ещё нет: строки — заглушки,
	// которые станут ссылками в следующих задачах.
	return (
		<SafeAreaView style={styles.screen} edges={["top"]} testID="library-screen">
			<Text style={styles.title}>{t("library.title")}</Text>
			<Text style={styles.hint}>{t("library.hint")}</Text>
			<View style={styles.list}>
				<Pressable
					disabled
					accessibilityRole="button"
					accessibilityState={{ disabled: true }}
					testID="library-collections"
					style={styles.row}
				>
					<Text style={styles.rowTitle}>{t("library.collections")}</Text>
					<Text style={styles.soon}>{t("library.soon")}</Text>
				</Pressable>
				<Pressable
					disabled
					accessibilityRole="button"
					accessibilityState={{ disabled: true }}
					testID="library-favorites"
					style={styles.row}
				>
					<Text style={styles.rowTitle}>{t("library.favorites")}</Text>
					<Text style={styles.soon}>{t("library.soon")}</Text>
				</Pressable>
			</View>
		</SafeAreaView>
	);
}

const styles = StyleSheet.create({
	screen: { flex: 1, padding: 16, gap: 12 },
	title: { fontSize: 24, fontWeight: "700" },
	hint: { fontSize: 14, opacity: 0.6 },
	list: { gap: 8, marginTop: 8 },
	row: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		padding: 16,
		borderWidth: 1,
		borderColor: "#8884",
		borderRadius: 10,
	},
	rowTitle: { fontSize: 16, fontWeight: "600" },
	soon: { fontSize: 12, opacity: 0.5 },
});

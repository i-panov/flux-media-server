import { router } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";

// Неизвестный deep link: без этого экрана expo-router показывает
// нелокализованную заглушку без пути назад.
export default function NotFoundScreen() {
	useLanguage();
	const { colors, spacing } = useTheme();
	return (
		<Screen edges={["top", "bottom"]} testID="not-found">
			<View style={[styles.content, { gap: spacing.md }]}>
				<Text style={[styles.title, { color: colors.text }]}>
					{t("common.notFound")}
				</Text>
				<Pressable
					accessibilityRole="button"
					hitSlop={8}
					testID="not-found-home"
					onPress={() => router.replace("/")}
					style={styles.linkButton}
				>
					<Text style={[styles.link, { color: colors.accent }]}>
						{t("common.back")}
					</Text>
				</Pressable>
			</View>
		</Screen>
	);
}

const styles = StyleSheet.create({
	content: { flex: 1, alignItems: "center", justifyContent: "center" },
	title: { fontSize: 18, fontWeight: "600" },
	linkButton: { minHeight: 44, justifyContent: "center" },
	link: { fontSize: 16, fontWeight: "600" },
});

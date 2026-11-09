import { StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useAudioList } from "../../src/api/media";
import { MediaList } from "../../src/components/MediaList";
import { t, useLanguage } from "../../src/i18n";

export default function AudioScreen() {
	useLanguage();
	const query = useAudioList();
	return (
		<SafeAreaView style={styles.screen} edges={["top"]}>
			<View style={styles.header}>
				<Text style={styles.title}>{t("audio.title")}</Text>
			</View>
			<MediaList query={query} />
		</SafeAreaView>
	);
}

const styles = StyleSheet.create({
	screen: { flex: 1, padding: 16, gap: 12 },
	header: { flexDirection: "row", alignItems: "center", gap: 12 },
	title: { fontSize: 24, fontWeight: "700" },
});

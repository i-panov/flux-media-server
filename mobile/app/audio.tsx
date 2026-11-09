import { router } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useAudioList } from "../src/api/media";
import { AuthGate } from "../src/components/AuthGate";
import { MediaList } from "../src/components/MediaList";
import { t, useLanguage } from "../src/i18n";

function AudioContent() {
	useLanguage();
	const query = useAudioList();
	return (
		<SafeAreaView style={styles.screen} edges={["top", "bottom"]}>
			<View style={styles.header}>
				<Pressable
					onPress={() =>
						router.canGoBack() ? router.back() : router.replace("/")
					}
				>
					<Text style={styles.back}>‹</Text>
				</Pressable>
				<Text style={styles.title}>{t("audio.title")}</Text>
			</View>
			<MediaList query={query} />
		</SafeAreaView>
	);
}

export default function AudioScreen() {
	return (
		<AuthGate>
			<AudioContent />
		</AuthGate>
	);
}

const styles = StyleSheet.create({
	screen: { flex: 1, padding: 16, gap: 12 },
	header: { flexDirection: "row", alignItems: "center", gap: 12 },
	title: { fontSize: 24, fontWeight: "700" },
	back: { fontSize: 30, lineHeight: 32 },
});

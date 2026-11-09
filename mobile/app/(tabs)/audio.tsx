import { StyleSheet, Text } from "react-native";
import { useAudioList } from "../../src/api/media";
import { MediaList } from "../../src/components/MediaList";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function AudioScreen() {
	useLanguage();
	const { colors } = useTheme();
	const query = useAudioList();
	return (
		<Screen>
			<Text style={[styles.title, { color: colors.text }]}>
				{t("audio.title")}
			</Text>
			<MediaList query={query} />
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
});

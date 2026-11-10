import { router } from "expo-router";
import { StyleSheet, Text } from "react-native";
import { useVideoList } from "../../src/api/media";
import { MediaList } from "../../src/components/MediaList";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function VideoScreen() {
	useLanguage();
	const { colors } = useTheme();
	const query = useVideoList();
	return (
		<Screen>
			<Text style={[styles.title, { color: colors.text }]}>
				{t("video.title")}
			</Text>
			<MediaList
				query={query}
				onPressItem={(item) => router.push(`/video/${item.id}`)}
			/>
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
});

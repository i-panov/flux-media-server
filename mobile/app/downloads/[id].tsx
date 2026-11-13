import Ionicons from "@expo/vector-icons/Ionicons";
import { router, useLocalSearchParams } from "expo-router";
import { useVideoPlayer, VideoView } from "expo-video";
import { Pressable, StyleSheet, Text, View } from "react-native";
import {
	useDownloadedPath,
	useDownloadState,
} from "../../src/downloads/DownloadProvider";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

// Локальный просмотр скачанного видео: не ходит в API и работает без сети.
export default function OfflineVideoScreen() {
	useLanguage();
	const { id } = useLocalSearchParams<{ id: string }>();
	const mediaId = Number(id);
	const entry = useDownloadState().entries.find(
		(item) => item.mediaId === mediaId,
	);
	const path = useDownloadedPath(mediaId);
	const { colors, spacing } = useTheme();
	const player = useVideoPlayer(path ?? "", (value) => {
		value.loop = false;
		value.play();
	});

	if (!Number.isFinite(mediaId) || path === null) {
		return (
			<View style={[styles.center, { backgroundColor: colors.background }]}>
				<Text style={{ color: colors.text }}>{t("downloads.empty")}</Text>
			</View>
		);
	}

	return (
		<View style={[styles.root, { backgroundColor: colors.background }]}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={() =>
					router.canGoBack() ? router.back() : router.replace("/downloads")
				}
				style={[styles.back, { padding: spacing.md }]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<VideoView
				player={player}
				style={styles.video}
				allowsPictureInPicture
				nativeControls
			/>
			<Text style={[styles.title, { color: colors.text }]} numberOfLines={2}>
				{entry?.title ?? ""}
			</Text>
		</View>
	);
}

const styles = StyleSheet.create({
	root: { flex: 1 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
	back: { alignSelf: "flex-start" },
	video: { width: "100%", aspectRatio: 16 / 9, backgroundColor: "#000" },
	title: { fontSize: 20, fontWeight: "700", padding: 16 },
});

import Ionicons from "@expo/vector-icons/Ionicons";
import * as FileSystem from "expo-file-system/legacy";
import { useKeepAwake } from "expo-keep-awake";
import { router, useLocalSearchParams } from "expo-router";
import { useVideoPlayer, VideoView } from "expo-video";
import { useEffect, useState } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
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
	const { entries, hydrated } = useDownloadState();
	const entry = entries.find((item) => item.mediaId === mediaId);
	const path = useDownloadedPath(mediaId);
	const { colors, spacing } = useTheme();
	const [fileMissing, setFileMissing] = useState(false);
	const [retry, setRetry] = useState(0);
	useKeepAwake();
	/* eslint-disable react-hooks/set-state-in-effect */
	// biome-ignore lint/correctness/useExhaustiveDependencies: retry — триггер повторной проверки файла.
	useEffect(() => {
		if (path === null) return;
		setFileMissing(false);
		void FileSystem.getInfoAsync(path).then((info) => {
			if (!info.exists) setFileMissing(true);
		});
	}, [path, retry]);
	/* eslint-enable react-hooks/set-state-in-effect */
	const player = useVideoPlayer(path ?? "", (value) => {
		value.loop = false;
		value.play();
	});

	if (
		!hydrated ||
		((!Number.isFinite(mediaId) || path === null) && !fileMissing)
	) {
		return (
			<View style={[styles.center, { backgroundColor: colors.background }]}>
				<ActivityIndicator color={colors.accent} />
			</View>
		);
	}
	if (!Number.isFinite(mediaId) || path === null || fileMissing) {
		return (
			<View
				style={[
					styles.center,
					{ backgroundColor: colors.background, gap: spacing.md },
				]}
			>
				<Text style={{ color: colors.text }}>{t("downloads.empty")}</Text>
				<Pressable
					accessibilityRole="button"
					onPress={() => setRetry((v) => v + 1)}
				>
					<Text style={{ color: colors.accent }}>{t("common.retry")}</Text>
				</Pressable>
				<Pressable
					accessibilityRole="button"
					onPress={() => router.replace("/downloads")}
				>
					<Text style={{ color: colors.accent }}>{t("common.back")}</Text>
				</Pressable>
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

import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { Image } from "expo-image";
import { useEffect, useState } from "react";
import { StyleSheet, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { coverPath, imageSource, thumbPath } from "../media/source";
import { useTheme } from "../theme/ThemeProvider";

interface AudioCoverProps {
	media: Media;
	size: number;
	testID?: string;
}

// Обложка полного/мини-плеера: media.cover_url без Bearer отдал бы 401,
// поэтому source собирается через authSource. Cover не у всех треков —
// при ошибке откатываемся на thumbnail, затем на иконку.
export function AudioCover({
	media,
	size,
	testID = "audio-cover",
}: AudioCoverProps) {
	useLanguage();
	const { colors, radii } = useTheme();
	const thumbnail = thumbPath(media.id);
	const preferred = media.cover_url === "" ? thumbnail : coverPath(media.id);
	// Fallback привязан к id: смена трека сама возвращает preferred, без
	// setState в эффекте (и лишнего каскадного рендера).
	const [fallback, setFallback] = useState<{ id: number; path: string } | null>(
		null,
	);
	const path = fallback?.id === media.id ? fallback.path : preferred;
	const [loaded, setLoaded] = useState<{
		path: string;
		source: Awaited<ReturnType<typeof imageSource>>;
	} | null>(null);
	const [failedPath, setFailedPath] = useState<string | null>(null);
	const failed = failedPath === path;

	useEffect(() => {
		let active = true;
		imageSource(path).then(
			(next) => {
				if (active) {
					setLoaded({ path, source: next });
				}
			},
			() => {
				if (active) {
					setLoaded(null);
				}
			},
		);
		return () => {
			active = false;
		};
	}, [path]);

	const source = loaded !== null && loaded.path === path ? loaded.source : null;

	return (
		<View
			testID={testID}
			accessible
			accessibilityLabel={t("audio.player.cover")}
			style={[
				styles.cover,
				{
					width: size,
					height: size,
					borderRadius: radii.md,
					backgroundColor: colors.surfaceMuted,
				},
			]}
		>
			{source === null || failed ? (
				<View style={styles.placeholder}>
					<Ionicons
						name="musical-notes-outline"
						size={Math.max(20, Math.round(size / 4))}
						color={colors.textMuted}
					/>
				</View>
			) : (
				<Image
					source={source}
					style={StyleSheet.absoluteFill}
					contentFit="cover"
					transition={150}
					accessibilityIgnoresInvertColors
					onError={() => {
						if (path !== thumbnail) {
							setFallback({ id: media.id, path: thumbnail });
							return;
						}
						setFailedPath(path);
					}}
				/>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	cover: { overflow: "hidden" },
	placeholder: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
	},
});

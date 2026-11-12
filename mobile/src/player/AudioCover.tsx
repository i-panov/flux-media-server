import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { Image } from "expo-image";
import { useEffect, useState } from "react";
import { StyleSheet, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { coverPath, imageSource } from "../media/source";
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
	// У аудио нет thumbnail: единственный источник обложки — cover_url.
	const path = media.cover_url === "" ? null : coverPath(media.id);
	const [loaded, setLoaded] = useState<{
		path: string;
		source: Awaited<ReturnType<typeof imageSource>>;
	} | null>(null);
	const [failedPath, setFailedPath] = useState<string | null>(null);
	const failed = failedPath === path;

	useEffect(() => {
		if (path === null) {
			return;
		}
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
					cachePolicy="none"
					transition={150}
					accessibilityIgnoresInvertColors
					onError={() => {
						if (path !== null) {
							setFailedPath(path);
						}
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

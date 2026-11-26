import { activeSubtitleText, parseWebVtt, type VttCue } from "@flux/shared";
import type { VideoPlayer as ExpoVideoPlayer } from "expo-video";
import { useEffect, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useMediaSubs } from "../api/subs";
import { t, useLanguage } from "../i18n";
import { fetchAuthedText } from "../media/source";
import { useTheme } from "../theme/ThemeProvider";

// Внешние .vtt expo-video не умеет: тянем дорожку сами и рисуем активный
// cue поверх видео. Тап по CC переключает «выкл → дорожка 1 → … → выкл».
export function SubtitleOverlay({
	mediaId,
	player,
}: {
	mediaId: number;
	player: ExpoVideoPlayer;
}) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const subs = useMediaSubs(mediaId);
	const tracks = subs.data ?? [];
	// -1 — субтитры выключены (по умолчанию, как у нативных контролов).
	const [trackIndex, setTrackIndex] = useState(-1);
	const [loaded, setLoaded] = useState<{ url: string; cues: VttCue[] } | null>(
		null,
	);
	const track = trackIndex >= 0 ? tracks[trackIndex] : undefined;
	const url = track?.url;
	// timeupdate плеера — раз в 0.5 с: для коротких реплик этого мало,
	// читаем currentTime чаще, пока субтитры включены.
	const [time, setTime] = useState(0);

	useEffect(() => {
		if (url === undefined) {
			return;
		}
		let active = true;
		void fetchAuthedText(url)
			.then((text) => {
				if (active) {
					setLoaded({ url, cues: parseWebVtt(text) });
				}
			})
			.catch(() => {
				if (active) {
					setLoaded({ url, cues: [] });
				}
			});
		return () => {
			active = false;
		};
	}, [url]);
	// Дорожка сменилась — старые cues игнорируем, не сбрасывая state в эффекте.
	const cues = loaded !== null && loaded.url === url ? loaded.cues : [];
	useEffect(() => {
		if (track === undefined) {
			return;
		}
		const timer = setInterval(() => setTime(player.currentTime), 200);
		return () => clearInterval(timer);
	}, [track, player]);

	if (tracks.length === 0) {
		return null;
	}
	const activeText =
		track === undefined ? null : activeSubtitleText(cues, time);
	const cycle = () => {
		setTrackIndex((prev) => (prev + 1 >= tracks.length ? -1 : prev + 1));
	};
	const label =
		track === undefined
			? t("player.subtitles")
			: `${t("player.subtitles")}: ${track.lang}`;

	return (
		<>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={label}
				accessibilityState={{ selected: track !== undefined }}
				testID="video-subtitles-toggle"
				onPress={cycle}
				style={[
					styles.toggle,
					{
						backgroundColor: colors.overlay,
						borderRadius: radii.sm,
						paddingHorizontal: spacing.xs,
					},
				]}
			>
				<Text style={[styles.toggleText, { color: colors.onOverlay }]}>
					{track === undefined ? "CC" : `CC ${track.lang}`}
				</Text>
			</Pressable>
			{activeText !== null && (
				<View pointerEvents="none" style={styles.captionWrap}>
					<Text style={styles.caption}>{activeText}</Text>
				</View>
			)}
		</>
	);
}

const styles = StyleSheet.create({
	toggle: {
		position: "absolute",
		top: 8,
		right: 8,
		minHeight: 32,
		justifyContent: "center",
	},
	toggleText: { fontSize: 12, fontWeight: "700" },
	captionWrap: {
		position: "absolute",
		left: 12,
		right: 12,
		bottom: 12,
		alignItems: "center",
	},
	caption: {
		backgroundColor: "rgba(0,0,0,0.65)",
		color: "#fff",
		fontSize: 16,
		lineHeight: 22,
		paddingHorizontal: 8,
		paddingVertical: 4,
		borderRadius: 6,
		textAlign: "center",
	},
});

import Ionicons from "@expo/vector-icons/Ionicons";
import type { RepeatMode } from "@flux/shared";
import { router } from "expo-router";
import type { ComponentProps } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { AudioCover } from "./AudioCover";
import { useAudioActions, useAudioState } from "./AudioProvider";
import { formatAudioTime } from "./audioLabels";
import { progressRatio } from "./videoControls";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

function repeatLabel(repeat: RepeatMode): string {
	switch (repeat) {
		case "all":
			return t("audio.player.repeatAll");
		case "one":
			return t("audio.player.repeatOne");
		default:
			return t("audio.player.repeatOff");
	}
}

interface BarButtonProps {
	icon: IoniconName;
	label: string;
	testID: string;
	onPress: () => void;
	primary?: boolean;
}

function BarButton({
	icon,
	label,
	testID,
	onPress,
	primary = false,
}: BarButtonProps) {
	const { colors, radii } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			onPress={onPress}
			testID={testID}
			hitSlop={4}
			style={({ pressed }) => [
				styles.button,
				primary && [
					styles.primary,
					{ backgroundColor: colors.accent, borderRadius: radii.pill },
				],
				pressed && styles.pressed,
			]}
		>
			<Ionicons
				name={icon}
				size={primary ? 22 : 20}
				color={primary ? colors.onAccent : colors.textMuted}
			/>
		</Pressable>
	);
}

// Глобальный мини-бар над табами. Показывает текущий трек и транспорт,
// тап по свободной области открывает полный плеер. Очередь пуста — бара нет.
export function AudioBar() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const {
		current,
		queue,
		index,
		displayPlaying,
		currentTime,
		duration,
		shuffle,
		repeat,
		error,
	} = useAudioState();
	const { toggle, next, clear } = useAudioActions();
	if (current === null) {
		return null;
	}
	const artists = current.artists.map((entry) => entry.name).join(", ");
	const showPause = displayPlaying;
	const modeLabel = [
		shuffle ? t("audio.player.shuffleOn") : "",
		repeat === "off" ? "" : repeatLabel(repeat),
	]
		.filter((entry) => entry !== "")
		.join(", ");

	return (
		<View
			style={[
				styles.bar,
				{
					backgroundColor: colors.surface,
					borderTopColor: colors.border,
					paddingHorizontal: spacing.md,
					paddingVertical: spacing.xs,
				},
			]}
		>
			<View
				style={[styles.progressTrack, { backgroundColor: colors.surfaceMuted }]}
			>
				<View
					style={[
						styles.progressFill,
						{
							backgroundColor: colors.accent,
							width: `${progressRatio(currentTime, duration) * 100}%`,
						},
					]}
				/>
			</View>
			<View style={[styles.row, { gap: spacing.sm }]}>
				<Pressable
					testID="audio-bar"
					accessibilityRole="button"
					accessibilityLabel={`${current.title} — ${t("audio.player.open")}`}
					onPress={() => router.push("/player")}
					style={[styles.openZone, { gap: spacing.sm }]}
				>
					<AudioCover media={current} size={44} testID="audio-bar-cover" />
					<View style={styles.info}>
						<View style={[styles.titleRow, { gap: spacing.xs }]}>
							<Text
								testID="audio-bar-title"
								numberOfLines={1}
								style={[styles.title, { color: colors.text }]}
							>
								{current.title}
							</Text>
							{error === null ? null : (
								<Ionicons
									name="alert-circle-outline"
									size={16}
									color={colors.danger}
									accessibilityLabel={error}
									testID="audio-bar-error"
								/>
							)}
						</View>
						<Text
							numberOfLines={1}
							style={[styles.muted, { color: colors.textMuted }]}
						>
							{artists === "" ? t("audio.player.unknownArtist") : artists}
						</Text>
						<View style={[styles.metaRow, { gap: spacing.sm }]}>
							<Text
								testID="audio-bar-index"
								style={[styles.muted, { color: colors.textMuted }]}
							>
								{`${index + 1}/${queue.length}`}
							</Text>
							<Text
								testID="audio-bar-time"
								style={[styles.muted, { color: colors.textMuted }]}
							>
								{`${formatAudioTime(currentTime)} / ${formatAudioTime(duration)}`}
							</Text>
							{modeLabel === "" ? null : (
								<Text
									numberOfLines={1}
									style={[styles.muted, styles.modes, { color: colors.accent }]}
								>
									{modeLabel}
								</Text>
							)}
						</View>
					</View>
				</Pressable>
				<View style={styles.actions}>
					<BarButton
						primary
						icon={showPause ? "pause" : "play"}
						label={showPause ? t("audio.player.pause") : t("audio.player.play")}
						testID={showPause ? "audio-bar-pause" : "audio-bar-play"}
						onPress={toggle}
					/>
					<BarButton
						icon="play-skip-forward"
						label={t("audio.player.next")}
						testID="audio-bar-next"
						onPress={next}
					/>
					<BarButton
						icon="close"
						label={t("audio.player.close")}
						testID="audio-bar-close"
						onPress={clear}
					/>
				</View>
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	bar: { borderTopWidth: 1, overflow: "hidden" },
	progressTrack: { position: "absolute", top: 0, left: 0, right: 0, height: 2 },
	progressFill: { position: "absolute", top: 0, bottom: 0, left: 0 },
	row: { flexDirection: "row", alignItems: "center" },
	openZone: { flex: 1, flexDirection: "row", alignItems: "center" },
	actions: { flexDirection: "row", alignItems: "center" },
	info: { flex: 1 },
	titleRow: { flexDirection: "row", alignItems: "center" },
	title: { flexShrink: 1, fontSize: 15, fontWeight: "600" },
	metaRow: { flexDirection: "row", alignItems: "center" },
	modes: { flexShrink: 1 },
	muted: { fontSize: 12 },
	button: {
		minHeight: 44,
		minWidth: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	primary: { width: 44, height: 44 },
	pressed: { opacity: 0.7 },
});

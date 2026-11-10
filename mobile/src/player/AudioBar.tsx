import Ionicons from "@expo/vector-icons/Ionicons";
import { formatDuration, type RepeatMode } from "@flux/shared";
import type { ComponentProps } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { useAudioPlayer } from "./AudioProvider";

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

function BarButton({
	icon,
	label,
	testID,
	onPress,
	active = false,
	primary = false,
	selected,
	badge,
}: {
	icon: IoniconName;
	label: string;
	testID: string;
	onPress: () => void;
	active?: boolean;
	primary?: boolean;
	selected?: boolean;
	badge?: string;
}) {
	const { colors, radii } = useTheme();
	const color = primary
		? colors.onAccent
		: active
			? colors.accent
			: colors.textMuted;
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			accessibilityState={selected === undefined ? undefined : { selected }}
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
			<Ionicons name={icon} size={primary ? 22 : 20} color={color} />
			{badge === undefined ? null : (
				<Text style={[styles.badge, { color }]}>{badge}</Text>
			)}
		</Pressable>
	);
}

// Компактный бар для вкладки «Аудио». Полный плеер и глобальный мини-бар
// появятся в Task 13; здесь достаточно транспорта и режимов очереди.
export function AudioBar() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const {
		current,
		queue,
		index,
		playing,
		currentTime,
		duration,
		shuffle,
		repeat,
		error,
		toggle,
		next,
		previous,
		toggleShuffle,
		cycleRepeat,
		clear,
	} = useAudioPlayer();
	if (current === null) {
		return null;
	}
	const artists = current.artists.map((entry) => entry.name).join(", ");
	return (
		<View
			testID="audio-bar"
			style={[
				styles.bar,
				{
					backgroundColor: colors.surface,
					borderColor: colors.border,
					borderRadius: radii.md,
					padding: spacing.sm,
					gap: spacing.xs,
				},
			]}
		>
			<View style={[styles.infoRow, { gap: spacing.sm }]}>
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
					<View style={[styles.subRow, { gap: spacing.xs }]}>
						<Text
							numberOfLines={1}
							style={[styles.muted, styles.artist, { color: colors.textMuted }]}
						>
							{artists === "" ? t("audio.player.unknownArtist") : artists}
						</Text>
						<Text
							testID="audio-bar-index"
							style={[styles.muted, { color: colors.textMuted }]}
						>
							{`${index + 1}/${queue.length}`}
						</Text>
					</View>
				</View>
				<Text
					testID="audio-bar-time"
					style={[styles.time, { color: colors.textMuted }]}
				>
					{`${formatDuration(currentTime)} / ${formatDuration(duration)}`}
				</Text>
			</View>
			<View style={[styles.buttons, { gap: spacing.xs }]}>
				<BarButton
					icon="play-skip-back"
					label={t("audio.player.previous")}
					testID="audio-bar-previous"
					onPress={previous}
				/>
				<BarButton
					primary
					icon={playing ? "pause" : "play"}
					label={playing ? t("audio.player.pause") : t("audio.player.play")}
					testID={playing ? "audio-bar-pause" : "audio-bar-play"}
					onPress={toggle}
				/>
				<BarButton
					icon="play-skip-forward"
					label={t("audio.player.next")}
					testID="audio-bar-next"
					onPress={next}
				/>
				<BarButton
					icon="shuffle"
					label={
						shuffle ? t("audio.player.shuffleOn") : t("audio.player.shuffleOff")
					}
					testID={shuffle ? "audio-bar-shuffle-on" : "audio-bar-shuffle-off"}
					onPress={toggleShuffle}
					active={shuffle}
					selected={shuffle}
				/>
				<BarButton
					icon="repeat"
					label={repeatLabel(repeat)}
					testID={`audio-bar-repeat-${repeat}`}
					onPress={cycleRepeat}
					active={repeat !== "off"}
					badge={repeat === "one" ? "1" : undefined}
				/>
				<BarButton
					icon="close"
					label={t("audio.player.close")}
					testID="audio-bar-close"
					onPress={clear}
				/>
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	bar: { borderWidth: 1 },
	infoRow: { flexDirection: "row", alignItems: "center" },
	info: { flex: 1 },
	titleRow: { flexDirection: "row", alignItems: "center" },
	subRow: { flexDirection: "row", alignItems: "center" },
	artist: { flexShrink: 1 },
	title: { flexShrink: 1, fontSize: 15, fontWeight: "600" },
	muted: { fontSize: 12 },
	time: { fontSize: 12, fontVariant: ["tabular-nums"] },
	buttons: { flexDirection: "row", alignItems: "center" },
	button: {
		flex: 1,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	primary: { flex: 0, width: 44, height: 44 },
	badge: {
		position: "absolute",
		right: 6,
		bottom: 3,
		fontSize: 9,
		fontWeight: "700",
	},
	pressed: { opacity: 0.7 },
});

import Ionicons from "@expo/vector-icons/Ionicons";
import type { RepeatMode } from "@flux/shared";
import type { ReactNode } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { AudioTimeline } from "./AudioTimeline";
import { repeatLabel, SEEK_STEP_SECONDS, seekLabel } from "./audioLabels";
import { clampSeek } from "./videoControls";

interface ControlButtonProps {
	children: ReactNode;
	label: string;
	testID: string;
	onPress: () => void;
	primary?: boolean;
	accessibilityValue?: {
		text?: string;
	};
	disabled?: boolean;
	selected?: boolean;
}

function ControlButton({
	children,
	label,
	testID,
	onPress,
	primary = false,
	accessibilityValue,
	disabled = false,
	selected,
}: ControlButtonProps) {
	const { colors, radii } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			accessibilityValue={accessibilityValue}
			accessibilityState={{ disabled, selected }}
			disabled={disabled}
			onPress={onPress}
			testID={testID}
			hitSlop={4}
			style={({ pressed }) => [
				styles.controlButton,
				primary && [
					styles.primaryButton,
					{ backgroundColor: colors.accent, borderRadius: radii.pill },
				],
				disabled && styles.disabled,
				pressed && styles.pressed,
			]}
		>
			{children}
		</Pressable>
	);
}

export interface AudioPlayerControlsProps {
	position: number;
	duration: number;
	displayPlaying: boolean;
	rate: number;
	shuffle: boolean;
	repeat: RepeatMode;
	favorite: boolean;
	favoriteDisabled: boolean;
	onSeekTo: (seconds: number) => void;
	onToggle: () => void;
	onNext: () => void;
	onPrevious: () => void;
	onCycleRate: () => void;
	onToggleShuffle: () => void;
	onCycleRepeat: () => void;
	onToggleFavorite: () => void;
	onOpenQueue: () => void;
}

export function AudioPlayerControls({
	position,
	duration,
	displayPlaying,
	rate,
	shuffle,
	repeat,
	favorite,
	favoriteDisabled,
	onSeekTo,
	onToggle,
	onNext,
	onPrevious,
	onCycleRate,
	onToggleShuffle,
	onCycleRepeat,
	onToggleFavorite,
	onOpenQueue,
}: AudioPlayerControlsProps) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const showPause = displayPlaying;

	const seekByStep = (delta: number) => {
		onSeekTo(clampSeek(position, delta, duration));
	};

	return (
		<View style={[styles.controls, { gap: spacing.sm }]}>
			<AudioTimeline
				position={position}
				duration={duration}
				onSeekTo={onSeekTo}
			/>
			<View style={[styles.buttons, { gap: spacing.xs }]}>
				<ControlButton
					label={t("audio.player.previous")}
					testID="audio-player-previous"
					onPress={onPrevious}
				>
					<Ionicons name="play-skip-back" size={22} color={colors.text} />
				</ControlButton>
				<ControlButton
					label={seekLabel(-SEEK_STEP_SECONDS)}
					testID="audio-player-back-10"
					onPress={() => seekByStep(-SEEK_STEP_SECONDS)}
				>
					<Ionicons name="play-back" size={22} color={colors.text} />
				</ControlButton>
				<ControlButton
					primary
					label={showPause ? t("audio.player.pause") : t("audio.player.play")}
					testID={showPause ? "audio-player-pause" : "audio-player-play"}
					onPress={onToggle}
				>
					<Ionicons
						name={showPause ? "pause" : "play"}
						size={26}
						color={colors.onAccent}
					/>
				</ControlButton>
				<ControlButton
					label={seekLabel(SEEK_STEP_SECONDS)}
					testID="audio-player-forward-10"
					onPress={() => seekByStep(SEEK_STEP_SECONDS)}
				>
					<Ionicons name="play-forward" size={22} color={colors.text} />
				</ControlButton>
				<ControlButton
					label={t("audio.player.next")}
					testID="audio-player-next"
					onPress={onNext}
				>
					<Ionicons name="play-skip-forward" size={22} color={colors.text} />
				</ControlButton>
			</View>
			<View style={[styles.buttons, { gap: spacing.xs }]}>
				<ControlButton
					label={t("audio.player.speed")}
					accessibilityValue={{ text: `${rate}×` }}
					testID="audio-player-speed"
					onPress={onCycleRate}
				>
					<Text style={[styles.rateText, { color: colors.text }]}>
						{`${rate}×`}
					</Text>
				</ControlButton>
				<ControlButton
					label={
						shuffle ? t("audio.player.shuffleOn") : t("audio.player.shuffleOff")
					}
					testID={
						shuffle ? "audio-player-shuffle-on" : "audio-player-shuffle-off"
					}
					onPress={onToggleShuffle}
					selected={shuffle}
				>
					<Ionicons
						name="shuffle"
						size={20}
						color={shuffle ? colors.accent : colors.textMuted}
					/>
				</ControlButton>
				<ControlButton
					label={repeatLabel(repeat)}
					testID={`audio-player-repeat-${repeat}`}
					onPress={onCycleRepeat}
					selected={repeat !== "off"}
				>
					<View style={styles.repeatWrap}>
						<Ionicons
							name="repeat"
							size={20}
							color={repeat === "off" ? colors.textMuted : colors.accent}
						/>
						{repeat === "one" && (
							<Text style={[styles.repeatBadge, { color: colors.accent }]}>
								1
							</Text>
						)}
					</View>
				</ControlButton>
				<ControlButton
					label={favorite ? t("media.unfavorite") : t("media.favorite")}
					testID={
						favorite ? "audio-player-favorite-on" : "audio-player-favorite-off"
					}
					onPress={onToggleFavorite}
					disabled={favoriteDisabled}
					selected={favorite}
				>
					<Ionicons
						name={favorite ? "heart" : "heart-outline"}
						size={22}
						color={favorite ? colors.favorite : colors.textMuted}
					/>
				</ControlButton>
				<ControlButton
					label={t("audio.player.queue")}
					testID="audio-player-queue"
					onPress={onOpenQueue}
				>
					<Ionicons name="list" size={22} color={colors.textMuted} />
				</ControlButton>
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	controls: { width: "100%" },
	buttons: { flexDirection: "row", alignItems: "center" },
	controlButton: {
		flex: 1,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	primaryButton: { flex: 0, width: 52, height: 52 },
	rateText: { fontSize: 13, fontWeight: "700", fontVariant: ["tabular-nums"] },
	repeatWrap: { alignItems: "center", justifyContent: "center" },
	repeatBadge: {
		position: "absolute",
		right: -5,
		bottom: -3,
		fontSize: 9,
		fontWeight: "700",
	},
	disabled: { opacity: 0.5 },
	pressed: { opacity: 0.7 },
});

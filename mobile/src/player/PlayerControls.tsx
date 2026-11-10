import Ionicons from "@expo/vector-icons/Ionicons";
import type { ReactNode } from "react";
import { useState } from "react";
import {
	type AccessibilityActionEvent,
	type AccessibilityValue,
	type GestureResponderEvent,
	type LayoutChangeEvent,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import {
	clampSeek,
	formatTime,
	progressRatio,
	timelineBounds,
} from "./videoControls";

const SEEK_STEP_SECONDS = 10;

function seekLabel(delta: number): string {
	return t(
		delta < 0 ? "video.player.seekBackward" : "video.player.seekForward",
		{ seconds: Math.abs(delta) },
	);
}

interface ControlButtonProps {
	children: ReactNode;
	label: string;
	testID: string;
	onPress: () => void;
	primary?: boolean;
	accessibilityValue?: AccessibilityValue;
}

function ControlButton({
	children,
	label,
	testID,
	onPress,
	primary = false,
	accessibilityValue,
}: ControlButtonProps) {
	const { colors, radii } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			accessibilityValue={accessibilityValue}
			onPress={onPress}
			testID={testID}
			hitSlop={4}
			style={({ pressed }) => [
				styles.controlButton,
				primary && [
					styles.primaryButton,
					{ backgroundColor: colors.accent, borderRadius: radii.pill },
				],
				pressed && styles.pressed,
			]}
		>
			{children}
		</Pressable>
	);
}

interface PlayerControlsProps {
	position: number;
	duration: number;
	isPlaying: boolean;
	rate: number;
	pipSupported: boolean;
	onSeekTo: (seconds: number) => void;
	onTogglePlayback: () => void;
	onReset: () => void;
	onCycleRate: () => void;
	onFullscreen: () => void;
	onPictureInPicture: () => void;
}

export function PlayerControls({
	position,
	duration,
	isPlaying,
	rate,
	pipSupported,
	onSeekTo,
	onTogglePlayback,
	onReset,
	onCycleRate,
	onFullscreen,
	onPictureInPicture,
}: PlayerControlsProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const [timelineWidth, setTimelineWidth] = useState(0);
	const bounds = timelineBounds(position, duration);

	const seekByStep = (delta: number) => {
		onSeekTo(clampSeek(position, delta, duration));
	};

	const handleTimelinePress = (event: GestureResponderEvent) => {
		if (duration <= 0 || timelineWidth <= 0) {
			return;
		}
		onSeekTo((event.nativeEvent.locationX / timelineWidth) * duration);
	};

	const handleTimelineLayout = (event: LayoutChangeEvent) => {
		setTimelineWidth(event.nativeEvent.layout.width);
	};

	const handleAccessibilityAction = (event: AccessibilityActionEvent) => {
		if (event.nativeEvent.actionName === "increment") {
			seekByStep(SEEK_STEP_SECONDS);
		} else if (event.nativeEvent.actionName === "decrement") {
			seekByStep(-SEEK_STEP_SECONDS);
		}
	};

	return (
		<View style={[styles.controls, { gap: spacing.xs, padding: spacing.sm }]}>
			<View style={[styles.timelineRow, { gap: spacing.sm }]}>
				<Text
					testID="video-player-position"
					style={[styles.time, { color: colors.onOverlay }]}
				>
					{formatTime(position)}
				</Text>
				<Pressable
					accessibilityRole="adjustable"
					accessibilityLabel={t("video.player.timeline")}
					accessibilityValue={{
						min: 0,
						max: bounds.max,
						now: bounds.now,
						text: `${formatTime(position)} / ${formatTime(duration)}`,
					}}
					accessibilityActions={[
						{ name: "decrement", label: seekLabel(-SEEK_STEP_SECONDS) },
						{ name: "increment", label: seekLabel(SEEK_STEP_SECONDS) },
					]}
					onAccessibilityAction={handleAccessibilityAction}
					onLayout={handleTimelineLayout}
					onPress={handleTimelinePress}
					testID="video-player-timeline"
					hitSlop={8}
					style={styles.timeline}
				>
					<View
						style={[
							styles.timelineTrack,
							{
								backgroundColor: colors.playerTrack,
								borderRadius: radii.pill,
							},
						]}
					>
						<View
							style={[
								styles.timelineFill,
								{
									// Заливка белая: accent на полупрозрачном треке даёт <3:1.
									backgroundColor: colors.onOverlay,
									width: `${progressRatio(position, duration) * 100}%`,
								},
							]}
						/>
					</View>
				</Pressable>
				<Text style={[styles.time, { color: colors.onOverlay }]}>
					{formatTime(duration)}
				</Text>
			</View>
			<View style={[styles.buttons, { gap: spacing.xs }]}>
				<ControlButton
					label={seekLabel(-SEEK_STEP_SECONDS)}
					testID="video-player-back-10"
					onPress={() => seekByStep(-SEEK_STEP_SECONDS)}
				>
					<Ionicons name="play-back" size={22} color={colors.onOverlay} />
				</ControlButton>
				<ControlButton
					primary
					label={isPlaying ? t("video.player.pause") : t("video.player.play")}
					testID="video-player-toggle"
					onPress={onTogglePlayback}
				>
					<Ionicons
						name={isPlaying ? "pause" : "play"}
						size={26}
						color={colors.onAccent}
					/>
				</ControlButton>
				<ControlButton
					label={seekLabel(SEEK_STEP_SECONDS)}
					testID="video-player-forward-10"
					onPress={() => seekByStep(SEEK_STEP_SECONDS)}
				>
					<Ionicons name="play-forward" size={22} color={colors.onOverlay} />
				</ControlButton>
				<ControlButton
					label={t("video.player.restart")}
					testID="video-player-restart"
					onPress={onReset}
				>
					<Ionicons name="refresh" size={22} color={colors.onOverlay} />
				</ControlButton>
				<ControlButton
					label={t("video.player.speed")}
					accessibilityValue={{ text: `${rate}×` }}
					testID="video-player-speed"
					onPress={onCycleRate}
				>
					<Text style={[styles.rateText, { color: colors.onOverlay }]}>
						{`${rate}×`}
					</Text>
				</ControlButton>
				<ControlButton
					label={t("video.player.fullscreen")}
					testID="video-player-fullscreen"
					onPress={onFullscreen}
				>
					<Ionicons name="expand-outline" size={22} color={colors.onOverlay} />
				</ControlButton>
				{pipSupported && (
					<ControlButton
						label={t("video.player.pictureInPicture")}
						testID="video-player-pip"
						onPress={onPictureInPicture}
					>
						<Ionicons
							name="browsers-outline"
							size={22}
							color={colors.onOverlay}
						/>
					</ControlButton>
				)}
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	controls: { width: "100%" },
	timelineRow: { flexDirection: "row", alignItems: "center" },
	time: {
		fontSize: 12,
		minWidth: 40,
		textAlign: "center",
		fontVariant: ["tabular-nums"],
	},
	timeline: { flex: 1, height: 24, justifyContent: "center" },
	timelineTrack: { height: 4, overflow: "hidden" },
	timelineFill: { position: "absolute", left: 0, top: 0, bottom: 0 },
	buttons: { flexDirection: "row", alignItems: "center" },
	controlButton: {
		flex: 1,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	primaryButton: { flex: 0, width: 48, height: 48 },
	rateText: { fontSize: 13, fontWeight: "600", fontVariant: ["tabular-nums"] },
	pressed: { opacity: 0.7 },
});

import { useState } from "react";
import {
	type AccessibilityActionEvent,
	type GestureResponderEvent,
	type LayoutChangeEvent,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { SEEK_STEP_SECONDS, seekLabel } from "./audioLabels";
import {
	clampSeek,
	formatTime,
	progressRatio,
	timelineBounds,
} from "./videoControls";

interface AudioTimelineProps {
	position: number;
	duration: number;
	onSeekTo: (seconds: number) => void;
}

// Таймлайн полного плеера: Pressable вместо slider — новых зависимостей
// нет, а accessibilityActions дают шаг ±10 без точного тапа.
export function AudioTimeline({
	position,
	duration,
	onSeekTo,
}: AudioTimelineProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const [timelineWidth, setTimelineWidth] = useState(0);
	const bounds = timelineBounds(position, duration);

	const seekBy = (delta: number) => {
		onSeekTo(clampSeek(position, delta, duration));
	};

	const handlePress = (event: GestureResponderEvent) => {
		if (duration <= 0 || timelineWidth <= 0) {
			return;
		}
		onSeekTo((event.nativeEvent.locationX / timelineWidth) * duration);
	};

	const handleLayout = (event: LayoutChangeEvent) => {
		setTimelineWidth(event.nativeEvent.layout.width);
	};

	const handleAction = (event: AccessibilityActionEvent) => {
		if (event.nativeEvent.actionName === "increment") {
			seekBy(SEEK_STEP_SECONDS);
		} else if (event.nativeEvent.actionName === "decrement") {
			seekBy(-SEEK_STEP_SECONDS);
		}
	};

	return (
		<View style={[styles.row, { gap: spacing.sm }]}>
			<Text
				testID="audio-player-position"
				style={[styles.time, { color: colors.textMuted }]}
			>
				{formatTime(position)}
			</Text>
			<Pressable
				accessibilityRole="adjustable"
				accessibilityLabel={t("audio.player.timeline")}
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
				onAccessibilityAction={handleAction}
				onLayout={handleLayout}
				onPress={handlePress}
				testID="audio-player-timeline"
				hitSlop={8}
				style={styles.timeline}
			>
				<View
					style={[
						styles.track,
						{ backgroundColor: colors.surfaceMuted, borderRadius: radii.pill },
					]}
				>
					<View
						style={[
							styles.fill,
							{
								backgroundColor: colors.accent,
								width: `${progressRatio(position, duration) * 100}%`,
							},
						]}
					/>
				</View>
			</Pressable>
			<Text
				testID="audio-player-duration"
				style={[styles.time, { color: colors.textMuted }]}
			>
				{formatTime(duration)}
			</Text>
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row", alignItems: "center" },
	time: {
		fontSize: 12,
		minWidth: 40,
		textAlign: "center",
		fontVariant: ["tabular-nums"],
	},
	timeline: { flex: 1, height: 28, justifyContent: "center" },
	track: { height: 4, overflow: "hidden" },
	fill: { position: "absolute", left: 0, top: 0, bottom: 0 },
});

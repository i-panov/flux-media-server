import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { useState } from "react";
import { Pressable, StyleSheet, Text } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { ClipSheet } from "./ClipSheet";

// Кнопка «Обрезать» на странице видео: держит шит и текущую позицию
// плеера, чтобы маркеры ставились по месту воспроизведения.
export function VideoClipAction({
	media,
	getPosition,
}: {
	media: Media;
	/** Позиция читается при открытии: timeupdate не должен ререндерить экран. */
	getPosition: () => number;
}) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const [open, setOpen] = useState(false);
	const [startAt, setStartAt] = useState(0);
	return (
		<>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("clip.submit")}
				testID="video-detail-clip"
				onPress={() => {
					setStartAt(getPosition());
					setOpen(true);
				}}
				style={({ pressed }) => [
					styles.action,
					{ gap: spacing.xs },
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="cut-outline" size={20} color={colors.accent} />
				<Text style={{ color: colors.accent }}>{t("clip.submit")}</Text>
			</Pressable>
			{open && (
				<ClipSheet
					media={media}
					position={startAt}
					duration={media.duration}
					onClose={() => setOpen(false)}
				/>
			)}
		</>
	);
}

const styles = StyleSheet.create({
	action: { alignItems: "center", minWidth: 88 },
	pressed: { opacity: 0.7 },
});

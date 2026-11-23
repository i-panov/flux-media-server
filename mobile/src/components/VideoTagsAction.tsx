import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { useState } from "react";
import { Pressable, StyleSheet, Text } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { TagsSheet } from "./TagsSheet";

// Теги на странице видео: на мобильном сетка не всегда открыта, поэтому
// действие живёт в админском блоке деталей.
export function VideoTagsAction({ media }: { media: Media }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const [open, setOpen] = useState(false);
	return (
		<>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("tags.title")}
				testID="video-detail-tags"
				onPress={() => setOpen(true)}
				style={({ pressed }) => [
					styles.action,
					{ gap: spacing.xs },
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="pricetags-outline" size={20} color={colors.accent} />
				<Text style={{ color: colors.accent }}>{t("tags.title")}</Text>
			</Pressable>
			{open && (
				<TagsSheet
					entity="media"
					id={media.id}
					title={media.title}
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

import type { Media } from "@flux/shared";
import { formatDuration } from "@flux/shared";
import { StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface MetaEntry {
	label: string;
	value: string;
}

// Метаданные видео: пустые значения не показываются, чтобы в строке не
// оставалось прочерков. Жанр приходит одной строкой из бэкенда.
export function VideoMeta({ media }: { media: Media }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const entries: MetaEntry[] = [];

	if (media.year > 0) {
		entries.push({ label: t("video.meta.year"), value: String(media.year) });
	}
	if (media.duration > 0) {
		entries.push({
			label: t("video.meta.duration"),
			value: formatDuration(media.duration),
		});
	}
	if (media.width > 0 && media.height > 0) {
		entries.push({
			label: t("video.meta.resolution"),
			value: `${media.width}×${media.height}`,
		});
	}
	if (media.genre !== "") {
		entries.push({ label: t("video.meta.genre"), value: media.genre });
	}

	if (entries.length === 0) {
		return null;
	}

	return (
		<View style={[styles.row, { gap: spacing.lg }]} testID="video-meta">
			{entries.map((entry) => (
				<View key={entry.label} style={styles.entry}>
					<Text style={[styles.label, { color: colors.textMuted }]}>
						{entry.label}
					</Text>
					<Text style={[styles.value, { color: colors.text }]}>
						{entry.value}
					</Text>
				</View>
			))}
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row", flexWrap: "wrap" },
	entry: { gap: 2 },
	label: { fontSize: 12, textTransform: "uppercase", letterSpacing: 0.4 },
	value: { fontSize: 14, fontWeight: "600" },
});

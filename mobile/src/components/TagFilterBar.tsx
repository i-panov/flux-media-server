import Ionicons from "@expo/vector-icons/Ionicons";
import { useState } from "react";
import {
	Modal,
	Pressable,
	ScrollView,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useTags } from "../api/tags";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { tvFocusStyle } from "../tv/focus";

type Mode = "format" | "genre";

interface TagFilterBarProps {
	formatID: number | null;
	genreIDs: number[];
	onFormatChange: (id: number | null) => void;
	onGenresChange: (ids: number[]) => void;
	/** Слаги форматов, которые на этой вкладке заведомо дадут пусто. */
	hiddenFormatSlugs?: string[];
	/** Только жанры: в каталоге формат задаётся вкладкой. */
	genresOnly?: boolean;
}

// Фильтры видео: формат (один) и жанры (много). Оба — теги с сервера,
// поэтому список общий и пустые группы просто не показываются.
export function TagFilterBar({
	formatID,
	genreIDs,
	onFormatChange,
	onGenresChange,
	hiddenFormatSlugs,
	genresOnly = false,
}: TagFilterBarProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const tags = useTags();
	const [mode, setMode] = useState<Mode | null>(null);

	const hidden = hiddenFormatSlugs ?? [];
	const formats = (tags.data ?? []).filter(
		(tag) => tag.group === "format" && !hidden.includes(tag.slug),
	);
	const genres = (tags.data ?? []).filter((tag) => tag.group === "genre");

	const formatName = formats.find((tag) => tag.id === formatID)?.name;
	const genreCount = genreIDs.length;

	const chip = (
		label: string,
		active: boolean,
		onPress: () => void,
		testID: string,
	) => (
		<Pressable
			key={testID}
			onPress={onPress}
			testID={testID}
			accessibilityRole="button"
			accessibilityLabel={label}
			accessibilityState={{ selected: active }}
			style={({ focused }) => [
				styles.chip,
				{
					borderColor: active ? colors.accent : colors.border,
					backgroundColor: active ? colors.surfaceMuted : colors.surface,
					borderRadius: radii.md,
				},
				tvFocusStyle(focused, colors.accent),
			]}
		>
			<Text
				numberOfLines={1}
				style={{ color: active ? colors.accent : colors.text, fontSize: 13 }}
			>
				{label}
			</Text>
			<Ionicons name="chevron-down" size={14} color={colors.textMuted} />
		</Pressable>
	);

	const options = mode === "format" ? formats : genres;
	return (
		<View style={{ gap: spacing.sm }}>
			<View style={[styles.row, { gap: spacing.sm }]}>
				{!genresOnly &&
					chip(
						formatName ?? t("video.allFormats"),
						formatID !== null,
						() => setMode("format"),
						"filter-format",
					)}
				{chip(
					genreCount > 0
						? t("video.genresCount", { count: genreCount })
						: t("video.allGenres"),
					genreCount > 0,
					() => setMode("genre"),
					"filter-genre",
				)}
			</View>
			<Modal
				visible={mode !== null}
				transparent
				animationType="fade"
				onRequestClose={() => setMode(null)}
			>
				<Pressable style={styles.backdrop} onPress={() => setMode(null)}>
					<Pressable
						style={[
							styles.sheet,
							{ backgroundColor: colors.surface, borderRadius: radii.lg },
						]}
						onPress={() => undefined}
					>
						<Text
							style={{ color: colors.text, fontSize: 16, fontWeight: "600" }}
						>
							{mode === "format"
								? t("video.formatFilter")
								: t("video.tagsFilter")}
						</Text>
						{mode === "format" && (
							<Pressable
								accessibilityRole="button"
								accessibilityState={{ selected: formatID === null }}
								onPress={() => {
									onFormatChange(null);
									setMode(null);
								}}
								style={styles.option}
								testID="filter-format-all"
							>
								<Text style={{ color: colors.text }}>
									{t("video.allFormats")}
								</Text>
								{formatID === null && (
									<Ionicons name="checkmark" size={18} color={colors.accent} />
								)}
							</Pressable>
						)}
						<ScrollView style={{ maxHeight: 320 }}>
							{options.length === 0 && (
								<Text style={{ color: colors.textMuted, padding: spacing.sm }}>
									{mode === "format"
										? t("video.noFormatTags")
										: t("video.noTags")}
								</Text>
							)}
							{options.map((tag) => {
								const active =
									mode === "format"
										? formatID === tag.id
										: genreIDs.includes(tag.id);
								return (
									<Pressable
										key={tag.id}
										testID={`filter-option-${tag.id}`}
										accessibilityRole="button"
										accessibilityState={{ selected: active }}
										onPress={() => {
											if (mode === "format") {
												onFormatChange(tag.id);
												setMode(null);
												return;
											}
											onGenresChange(
												active
													? genreIDs.filter((id) => id !== tag.id)
													: [...genreIDs, tag.id],
											);
										}}
										style={styles.option}
									>
										<Text style={{ color: colors.text }}>{tag.name}</Text>
										{active && (
											<Ionicons
												name="checkmark"
												size={18}
												color={colors.accent}
											/>
										)}
									</Pressable>
								);
							})}
						</ScrollView>
						{mode === "genre" && (
							<Pressable
								onPress={() => setMode(null)}
								style={[
									styles.done,
									{ backgroundColor: colors.accent, borderRadius: radii.md },
								]}
								testID="filter-genre-done"
							>
								<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
									{t("common.save")}
								</Text>
							</Pressable>
						)}
					</Pressable>
				</Pressable>
			</Modal>
		</View>
	);
}

const styles = StyleSheet.create({
	row: { flexDirection: "row" },
	chip: {
		flexDirection: "row",
		alignItems: "center",
		gap: 4,
		borderWidth: 1,
		paddingHorizontal: 10,
		paddingVertical: 6,
		maxWidth: "48%",
	},
	backdrop: {
		flex: 1,
		backgroundColor: "rgba(0,0,0,0.4)",
		justifyContent: "center",
		padding: 24,
	},
	sheet: { padding: 16, gap: 8 },
	option: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		paddingVertical: 10,
	},
	done: { alignItems: "center", paddingVertical: 12 },
});

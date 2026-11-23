import { Pressable, ScrollView, StyleSheet, Text } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

export type VideoTab =
	| "videos"
	| "films"
	| "series"
	| "film_series"
	| "franchises";

const TABS: VideoTab[] = [
	"videos",
	"films",
	"series",
	"film_series",
	"franchises",
];

function label(tab: VideoTab): string {
	switch (tab) {
		case "films":
			return t("video.tabFilms");
		case "series":
			return t("video.tabSeries");
		case "film_series":
			return t("video.tabFilmSeries");
		case "franchises":
			return t("video.tabFranchises");
		default:
			return t("video.tabVideos");
	}
}

// Вкладки видео-раздела как в вебе: общая сетка, фильмы, сериалы,
// серии фильмов и франшизы.
export function VideoTabs({
	value,
	onChange,
}: {
	value: VideoTab;
	onChange: (tab: VideoTab) => void;
}) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	return (
		<ScrollView
			horizontal
			showsHorizontalScrollIndicator={false}
			contentContainerStyle={{ gap: spacing.xs }}
		>
			{TABS.map((tab) => {
				const active = tab === value;
				return (
					<Pressable
						key={tab}
						testID={`video-tab-${tab}`}
						onPress={() => onChange(tab)}
						style={[
							styles.tab,
							{
								borderRadius: radii.md,
								borderColor: active ? colors.accent : colors.border,
								backgroundColor: active ? colors.accent : colors.surface,
							},
						]}
					>
						<Text
							style={{
								color: active ? colors.onAccent : colors.text,
								fontSize: 13,
								fontWeight: active ? "600" : "400",
							}}
						>
							{label(tab)}
						</Text>
					</Pressable>
				);
			})}
		</ScrollView>
	);
}

const styles = StyleSheet.create({
	tab: { borderWidth: 1, paddingHorizontal: 12, paddingVertical: 7 },
});

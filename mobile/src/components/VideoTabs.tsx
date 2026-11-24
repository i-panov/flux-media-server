import { Pressable, ScrollView, StyleSheet, Text } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { tvFocusStyle } from "../tv/focus";

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
			// flexShrink: 0 обязателен: иначе в колонке экрана ScrollView
			// сжимается по высоте и обрезает подписи вкладок.
			style={{ flexGrow: 0, flexShrink: 0 }}
			contentContainerStyle={{
				gap: spacing.xs,
				alignItems: "center",
				paddingRight: spacing.md,
			}}
		>
			{TABS.map((tab) => {
				const active = tab === value;
				return (
					<Pressable
						key={tab}
						testID={`video-tab-${tab}`}
						accessibilityRole="tab"
						accessibilityState={{ selected: active }}
						accessibilityLabel={label(tab)}
						onPress={() => onChange(tab)}
						style={({ focused }) => [
							styles.tab,
							{
								borderRadius: radii.md,
								borderColor: active ? colors.accent : colors.border,
								backgroundColor: active ? colors.accent : colors.surface,
							},
							tvFocusStyle(focused, colors.accent),
						]}
					>
						<Text
							style={{
								color: active ? colors.onAccent : colors.text,
								fontSize: 13,
								fontWeight: active ? "600" : "400",
								// Android добавляет вертикальный font padding,
								// из-за которого при крупном системном шрифте
								// подпись выглядит подрезанной.
								includeFontPadding: false,
								textAlignVertical: "center",
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
	tab: {
		borderWidth: 1,
		minHeight: 34,
		paddingHorizontal: 12,
		paddingVertical: 7,
		alignItems: "center",
		justifyContent: "center",
	},
});

import { useMemo } from "react";
import { StyleSheet, Text } from "react-native";
import { useAudioList } from "../../src/api/media";
import { MediaList } from "../../src/components/MediaList";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useAudioActions } from "../../src/player/AudioProvider";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function AudioScreen() {
	useLanguage();
	const { colors } = useTheme();
	const query = useAudioList();
	// Только stable actions-контекст: вкладка не перерисовывается каждые
	// 500 мс от currentTime мини-плеера.
	const { playQueue } = useAudioActions();
	// Очередь стартует из уже загруженных страниц списка: пользователь
	// слышит порядок, который видит, а не весь каталог.
	const items = useMemo(
		() => query.data?.pages.flatMap((page) => page.items) ?? [],
		[query.data],
	);

	return (
		<Screen>
			<Text style={[styles.title, { color: colors.text }]}>
				{t("audio.title")}
			</Text>
			<MediaList
				query={query}
				onPressItem={(item) => {
					const startIndex = items.findIndex(
						(candidate) => candidate.id === item.id,
					);
					playQueue(items, Math.max(startIndex, 0));
				}}
			/>
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
});

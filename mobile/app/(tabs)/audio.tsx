import { useMemo } from "react";
import { StyleSheet, Text } from "react-native";
import { useAudioList } from "../../src/api/media";
import { MediaList } from "../../src/components/MediaList";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { AudioBar } from "../../src/player/AudioBar";
import { useAudioPlayer } from "../../src/player/AudioProvider";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function AudioScreen() {
	useLanguage();
	const { colors } = useTheme();
	const query = useAudioList();
	const { playQueue } = useAudioPlayer();
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
			{/* Пока бар живёт на экране аудио; глобальный мини-бар над
			    табами переносится в Task 13. */}
			<AudioBar />
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
});

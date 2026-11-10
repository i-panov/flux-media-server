import { router } from "expo-router";
import { useMemo } from "react";
import { useFavoriteAudioIds } from "../../src/api/favorites";
import { useAudioList } from "../../src/api/media";
import { AudioHomeRows } from "../../src/components/HomeRows";
import { MediaList } from "../../src/components/MediaList";
import { Screen } from "../../src/components/Screen";
import { SectionHeader } from "../../src/components/SectionHeader";
import { t, useLanguage } from "../../src/i18n";
import { excludeMediaIds } from "../../src/media/visibleMedia";
import { useAudioActions } from "../../src/player/AudioProvider";

export default function AudioScreen() {
	useLanguage();
	const query = useAudioList();
	// Только stable actions-контекст: вкладка не перерисовывается каждые
	// 500 мс от currentTime мини-плеера.
	const { playQueue } = useAudioActions();
	const favorites = useFavoriteAudioIds();
	// Очередь стартует из уже загруженных страниц списка: пользователь
	// слышит порядок, который видит, а не весь каталог. Избранное уже
	// показано рядом выше, поэтому из очереди оно исключено.
	const items = useMemo(
		() =>
			excludeMediaIds(
				query.data?.pages.flatMap((page) => page.items) ?? [],
				favorites.data,
			),
		[query.data, favorites.data],
	);

	return (
		<Screen>
			<SectionHeader
				title={t("audio.title")}
				titleStyle={{ fontSize: 24 }}
				actionLabel={t("artists.title")}
				onActionPress={() => router.push("/artists")}
				actionTestID="audio-open-artists"
			/>
			<MediaList
				query={query}
				ListHeaderComponent={<AudioHomeRows />}
				excludedIds={favorites.data}
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

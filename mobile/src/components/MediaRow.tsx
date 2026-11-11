import type { Media } from "@flux/shared";
import { FlatList, StyleSheet, View } from "react-native";
import { coverPath, thumbPath } from "../media/source";
import { useAuthImageSource } from "../media/useAuthImageSource";
import { useTheme } from "../theme/ThemeProvider";
import { HOME_ROW_LIMIT, isRowVisible } from "./homeRows";
import { MediaCard, type MediaCardVariant } from "./MediaCard";
import { SectionHeader } from "./SectionHeader";

const ROW_CARD_WIDTH = 148;

export interface MediaRowItem {
	media: Media;
	/** Доля просмотра/прослушивания 0..1. */
	progress?: number;
	isFavorite?: boolean;
	/** База testID карточки, например continue-card-42. */
	testID: string;
}

interface MediaRowProps {
	title: string;
	items: readonly MediaRowItem[];
	testID: string;
	onPressItem: (item: MediaRowItem) => void;
	onFavoriteItem?: (item: MediaRowItem) => void;
}

function variantOf(media: Media): MediaCardVariant {
	return media.type === "audio" ? "audio" : "video";
}

function RowCard({
	item,
	onPress,
	onFavoritePress,
}: {
	item: MediaRowItem;
	onPress: () => void;
	onFavoritePress?: () => void;
}) {
	const { spacing } = useTheme();
	// Cover есть не у всех записей: миниатюра — дешёвый fallback, а
	// битую картинку MediaCard заменит заглушкой. Обложка меняется по тому
	// же URL, поэтому кеш для неё отключён.
	const hasCover = item.media.cover_url !== "";
	const path = hasCover ? coverPath(item.media.id) : thumbPath(item.media.id);
	const source = useAuthImageSource(path);
	const artists = item.media.artists.map((artist) => artist.name).join(", ");

	return (
		<MediaCard
			title={item.media.title}
			subtitle={artists === "" ? item.media.album : artists}
			duration={item.media.duration}
			progress={item.progress}
			variant={variantOf(item.media)}
			imageSource={source}
			imageCachePolicy={hasCover ? "none" : "memory-disk"}
			isFavorite={item.isFavorite}
			onPress={onPress}
			onFavoritePress={onFavoritePress}
			testID={item.testID}
			style={{ width: ROW_CARD_WIDTH, marginRight: spacing.sm }}
		/>
	);
}

// Горизонтальный ряд карточек над основным списком. Пустой ряд не
// рендерится: заголовок без содержимого только отвлекает.
export function MediaRow({
	title,
	items,
	testID,
	onPressItem,
	onFavoriteItem,
}: MediaRowProps) {
	const { spacing } = useTheme();
	if (!isRowVisible(items)) {
		return null;
	}
	const visibleItems = items.slice(0, HOME_ROW_LIMIT);
	return (
		<View style={{ gap: spacing.sm }} testID={testID}>
			<SectionHeader title={title} titleStyle={styles.title} />
			<FlatList
				horizontal
				showsHorizontalScrollIndicator={false}
				data={visibleItems}
				keyExtractor={(item) => String(item.media.id)}
				accessibilityRole="list"
				renderItem={({ item }) => (
					<RowCard
						item={item}
						onPress={() => onPressItem(item)}
						onFavoritePress={
							onFavoriteItem === undefined
								? undefined
								: () => onFavoriteItem(item)
						}
					/>
				)}
			/>
		</View>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 16, fontWeight: "700" },
});

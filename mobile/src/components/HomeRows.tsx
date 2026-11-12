import Ionicons from "@expo/vector-icons/Ionicons";
import type { Collection, Media } from "@flux/shared";
import { router } from "expo-router";
import { Alert, Pressable, Text, View } from "react-native";
import { useAudioCollections, useVideoCollections } from "../api/collections";
import {
	useFavoriteMedia,
	useFavoriteMediaIds,
	useToggleVideoFavorite,
} from "../api/favorites";
import { useContinueWatching } from "../api/progress";
import { t, useLanguage } from "../i18n";
import { AudioCover } from "../player/AudioCover";
import { useAudioActions } from "../player/AudioProvider";
import { useTheme } from "../theme/ThemeProvider";
import { CollectionRow } from "./CollectionRow";
import {
	continueProgressRatio,
	isRowVisible,
	rootCollections,
} from "./homeRows";
import { MediaRow, type MediaRowItem } from "./MediaRow";
import { SectionHeader } from "./SectionHeader";

const EMPTY_IDS: ReadonlySet<number> = new Set<number>();

function openCollection(collection: Collection): void {
	router.push(`/collections/${collection.id}`);
}

function openVideo(media: Media): void {
	router.push(`/video/${media.id}`);
}

export function VideoHomeRows({ hidden = false }: { hidden?: boolean }) {
	useLanguage();
	const { spacing } = useTheme();
	const continueQuery = useContinueWatching("video");
	const favorites = useFavoriteMedia("video");
	const favoriteIds = useFavoriteMediaIds("video");
	const collections = useVideoCollections();
	const toggleFavorite = useToggleVideoFavorite();
	const favoriteSet = favoriteIds.data ?? EMPTY_IDS;

	// Не размонтируем ряды при поиске: компонент остаётся в дереве и
	// просто не рендерит содержимое, чтобы сброс поиска не поднимал
	// заново запросы продолжения/избранного/коллекций.
	if (hidden) {
		return null;
	}

	const onToggleFavorite = (item: MediaRowItem) => {
		toggleFavorite.mutate(
			{
				mediaId: item.media.id,
				favorite: item.isFavorite === true,
				media: item.media,
			},
			{ onError: () => Alert.alert(t("video.favoriteError")) },
		);
	};

	const continueItems: MediaRowItem[] = (continueQuery.data ?? []).map(
		(entry) => ({
			media: entry.media,
			progress: continueProgressRatio(entry, entry.media.duration),
			isFavorite: favoriteSet.has(entry.media.id),
			testID: `continue-card-${entry.media.id}`,
		}),
	);
	const favoriteItems: MediaRowItem[] = favorites.map((media) => ({
		media,
		isFavorite: true,
		testID: `favorite-card-${media.id}`,
	}));
	const roots = rootCollections(collections.data ?? [], "video");

	return (
		<View style={{ gap: spacing.lg, marginBottom: spacing.lg }}>
			<MediaRow
				title={t("continue.watching")}
				items={continueItems}
				testID="continue-row"
				onPressItem={(item) => openVideo(item.media)}
				onFavoriteItem={onToggleFavorite}
			/>
			<MediaRow
				title={t("favorites.title")}
				items={favoriteItems}
				testID="favorite-row"
				onPressItem={(item) => openVideo(item.media)}
				onFavoriteItem={onToggleFavorite}
			/>
			<CollectionRow
				collections={roots}
				testID="collections-row"
				onPressCollection={openCollection}
			/>
		</View>
	);
}

function AudioHomeList({
	title,
	items,
	testID,
	onPressItem,
	onMenuItem,
}: {
	title: string;
	items: readonly MediaRowItem[];
	testID: string;
	onPressItem: (item: MediaRowItem) => void;
	onMenuItem: (item: MediaRowItem) => void;
}) {
	const { colors, spacing } = useTheme();
	if (!isRowVisible(items)) return null;
	return (
		<View style={{ gap: spacing.sm }} testID={testID}>
			<SectionHeader
				title={title}
				titleStyle={{ fontSize: 16, fontWeight: "700" }}
			/>
			<View style={{ gap: spacing.xs }}>
				{items.map((item) => (
					<View
						key={item.media.id}
						style={{
							flexDirection: "row",
							alignItems: "center",
							gap: spacing.sm,
							padding: spacing.sm,
							borderWidth: 1,
							borderColor: colors.border,
							borderRadius: 10,
							backgroundColor: colors.surface,
						}}
					>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={item.media.title}
							onPress={() => onPressItem(item)}
							style={{
								flex: 1,
								flexDirection: "row",
								alignItems: "center",
								gap: spacing.sm,
							}}
						>
							<AudioCover media={item.media} size={48} />
							<View style={{ flex: 1 }}>
								<Text
									numberOfLines={1}
									style={{
										color: colors.text,
										fontSize: 15,
										fontWeight: "600",
									}}
								>
									{item.media.title}
								</Text>
								<Text
									numberOfLines={1}
									style={{ color: colors.textMuted, fontSize: 12 }}
								>
									{item.media.artists.map((artist) => artist.name).join(", ") ||
										t("audio.player.unknownArtist")}
								</Text>
							</View>
						</Pressable>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("media.actions")}
							onPress={() => onMenuItem(item)}
							hitSlop={8}
							testID={`audio-home-${item.media.id}-menu`}
						>
							<Ionicons
								name="ellipsis-horizontal"
								size={20}
								color={colors.textMuted}
							/>
						</Pressable>
					</View>
				))}
			</View>
		</View>
	);
}

export function AudioHomeRows({
	hidden = false,
	onMenuItem,
}: {
	hidden?: boolean;
	onMenuItem: (media: Media) => void;
}) {
	useLanguage();
	const { spacing } = useTheme();
	const favorites = useFavoriteMedia("audio");
	const collections = useAudioCollections();
	const { playQueue } = useAudioActions();

	if (hidden) {
		return null;
	}

	const play = (media: Media) => {
		playQueue([media], 0);
	};

	const favoriteItems: MediaRowItem[] = favorites.map((media) => ({
		media,
		isFavorite: true,
		testID: `favorite-card-${media.id}`,
	}));
	const roots = rootCollections(collections.data ?? [], "audio");

	return (
		<View style={{ gap: spacing.lg }}>
			<AudioHomeList
				title={t("favorites.title")}
				items={favoriteItems}
				testID="favorite-row"
				onPressItem={(item) => play(item.media)}
				onMenuItem={(item) => onMenuItem(item.media)}
			/>
			<CollectionRow
				collections={roots}
				testID="collections-row"
				onPressCollection={openCollection}
			/>
		</View>
	);
}

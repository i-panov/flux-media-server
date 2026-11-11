import type { Collection, Media } from "@flux/shared";
import { router } from "expo-router";
import { Alert, View } from "react-native";
import { useAudioCollections, useVideoCollections } from "../api/collections";
import {
	useFavoriteMedia,
	useFavoriteMediaIds,
	useToggleAudioFavorite,
	useToggleVideoFavorite,
} from "../api/favorites";
import { useContinueWatching } from "../api/progress";
import { t, useLanguage } from "../i18n";
import { useAudioActions } from "../player/AudioProvider";
import { useTheme } from "../theme/ThemeProvider";
import { CollectionRow } from "./CollectionRow";
import { continueProgressRatio, rootCollections } from "./homeRows";
import { MediaRow, type MediaRowItem } from "./MediaRow";

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
		<View style={{ gap: spacing.lg }}>
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

export function AudioHomeRows({ hidden = false }: { hidden?: boolean }) {
	useLanguage();
	const { spacing } = useTheme();
	const continueQuery = useContinueWatching("audio");
	const favorites = useFavoriteMedia("audio");
	const favoriteIds = useFavoriteMediaIds("audio");
	const collections = useAudioCollections();
	const toggleFavorite = useToggleAudioFavorite();
	const { playQueue } = useAudioActions();
	const favoriteSet = favoriteIds.data ?? EMPTY_IDS;

	if (hidden) {
		return null;
	}

	const play = (media: Media) => {
		playQueue([media], 0);
		router.push("/player");
	};

	const onToggleFavorite = (item: MediaRowItem) => {
		toggleFavorite.mutate(
			{
				mediaId: item.media.id,
				favorite: item.isFavorite === true,
				media: item.media,
			},
			{ onError: () => Alert.alert(t("audio.player.favoriteError")) },
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
	const roots = rootCollections(collections.data ?? [], "audio");

	return (
		<View style={{ gap: spacing.lg }}>
			<MediaRow
				title={t("continue.listening")}
				items={continueItems}
				testID="continue-row"
				onPressItem={(item) => play(item.media)}
				onFavoriteItem={onToggleFavorite}
			/>
			<MediaRow
				title={t("favorites.title")}
				items={favoriteItems}
				testID="favorite-row"
				onPressItem={(item) => play(item.media)}
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

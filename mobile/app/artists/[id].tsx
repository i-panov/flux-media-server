import Ionicons from "@expo/vector-icons/Ionicons";
import { router, useLocalSearchParams } from "expo-router";
import { useMemo, useState } from "react";
import {
	ActivityIndicator,
	Alert,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import {
	useFavoriteArtistIds,
	useToggleArtistFavorite,
} from "../../src/api/favorites";
import { useArtistTracks } from "../../src/api/media";
import { type ArtistEntry, useArtist } from "../../src/api/metadata";
import { parseArtistIdParam } from "../../src/artists/artistView";
import { useSession } from "../../src/auth/session";
import { ArtistCover } from "../../src/components/ArtistCover";
import { ArtistFavoriteButton } from "../../src/components/ArtistFavoriteButton";
import { AuthGate } from "../../src/components/AuthGate";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import { InlineError } from "../../src/components/InlineError";
import { MediaList } from "../../src/components/MediaList";
import { RenameArtistModal } from "../../src/components/RenameArtistModal";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useAudioActions } from "../../src/player/AudioProvider";
import { useTheme } from "../../src/theme/ThemeProvider";

// Deep link может открыть артиста первым — назад ведёт к списку артистов.
function closeArtist(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/artists");
}

function ArtistNavHeader() {
	const { colors } = useTheme();
	return (
		<View style={styles.header}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={closeArtist}
				testID="artist-back"
				hitSlop={8}
				style={({ pressed }) => [
					styles.headerButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<Text style={[styles.headerTitle, { color: colors.textMuted }]}>
				{t("artists.artist")}
			</Text>
			<View style={styles.headerButton} />
		</View>
	);
}

function ArtistHero({
	artist,
	isAdmin,
	favorite,
	favoriteDisabled,
	onToggleFavorite,
	onRename,
}: {
	artist: ArtistEntry;
	isAdmin: boolean;
	favorite: boolean;
	favoriteDisabled: boolean;
	onToggleFavorite: () => void;
	onRename: () => void;
}) {
	const { colors, radii, spacing } = useTheme();
	return (
		<View style={[styles.hero, { gap: spacing.md }]}>
			<ArtistCover artist={artist} size={96} testID="artist-detail-cover" />
			<View style={[styles.heroInfo, { gap: spacing.xs }]}>
				<Text
					testID="artist-detail-name"
					numberOfLines={3}
					style={[styles.name, { color: colors.text }]}
				>
					{artist.name}
				</Text>
				<View style={[styles.heroActions, { gap: spacing.xs }]}>
					<ArtistFavoriteButton
						artistName={artist.name}
						active={favorite}
						disabled={favoriteDisabled}
						testID="artist-detail-favorite"
						onPress={onToggleFavorite}
					/>
					{isAdmin && (
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("artists.rename")}
							onPress={onRename}
							testID="artist-rename"
							hitSlop={4}
							style={({ pressed }) => [
								styles.renameButton,
								{
									borderColor: colors.borderStrong,
									borderRadius: radii.sm,
									paddingHorizontal: spacing.md,
								},
								pressed && styles.pressed,
							]}
						>
							<Ionicons name="create-outline" size={18} color={colors.text} />
							<Text style={[styles.renameLabel, { color: colors.text }]}>
								{t("artists.rename")}
							</Text>
						</Pressable>
					)}
				</View>
			</View>
		</View>
	);
}

export default function ArtistScreen() {
	return (
		<AuthGate>
			<ArtistContent />
		</AuthGate>
	);
}

function ArtistContent() {
	useLanguage();
	const { colors } = useTheme();
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const artistId = parseArtistIdParam(params.id);
	const valid = artistId !== null;
	const { artist, hasData, isPending, isError, refetch } = useArtist(
		artistId ?? 0,
		valid,
	);
	const tracks = useArtistTracks(artistId ?? 0, valid);
	const favorites = useFavoriteArtistIds();
	const toggleFavorite = useToggleArtistFavorite();
	const session = useSession();
	const { playQueue } = useAudioActions();
	const [renameOpen, setRenameOpen] = useState(false);
	const items = useMemo(
		() => tracks.data?.pages.flatMap((page) => page.items) ?? [],
		[tracks.data],
	);

	const header = <ArtistNavHeader />;
	const favoriteIds = favorites.data ?? new Set<number>();
	const isAdmin = session.data?.is_admin === true;
	const favoriteBusy =
		favorites.isPending || favorites.isFetching || toggleFavorite.isPending;

	if (!valid) {
		return (
			<Screen testID="artist-screen" edges={["top", "bottom"]}>
				{header}
				<EmptyState
					icon="person-outline"
					title={t("artists.notFound")}
					description={t("artists.notFoundHint")}
					testID="artist-not-found"
				/>
			</Screen>
		);
	}

	if (isPending) {
		return (
			<Screen testID="artist-screen" edges={["top", "bottom"]}>
				{header}
				<View style={styles.center}>
					<ActivityIndicator color={colors.accent} />
				</View>
			</Screen>
		);
	}

	// Полный ErrorState — только без загруженного справочника. Если данные
	// уже есть, ошибка рефетча не должна прятать карточку и треки.
	if (isError && !hasData) {
		return (
			<Screen testID="artist-screen" edges={["top", "bottom"]}>
				{header}
				<ErrorState
					title={t("artists.loadError")}
					onRetry={() => void refetch()}
					retryTestID="artist-retry"
					testID="artist-error"
				/>
			</Screen>
		);
	}

	if (artist === undefined) {
		return (
			<Screen testID="artist-screen" edges={["top", "bottom"]}>
				{header}
				<EmptyState
					icon="person-outline"
					title={t("artists.notFound")}
					description={t("artists.notFoundHint")}
					testID="artist-not-found"
				/>
			</Screen>
		);
	}

	const onToggleFavorite = () => {
		toggleFavorite.mutate(
			{ artistId: artist.id, favorite: favoriteIds.has(artist.id) },
			{ onError: () => Alert.alert(t("artists.favoriteError")) },
		);
	};

	const onPressTrack = (mediaId: number) => {
		const startIndex = items.findIndex((item) => item.id === mediaId);
		playQueue(items, Math.max(startIndex, 0));
	};

	return (
		<Screen testID="artist-screen" edges={["top", "bottom"]}>
			{header}
			{isError && (
				<InlineError
					message={t("artists.loadError")}
					onRetry={() => void refetch()}
					testID="artist-inline-error"
					retryTestID="artist-inline-retry"
				/>
			)}
			<ArtistHero
				artist={artist}
				isAdmin={isAdmin}
				favorite={favoriteIds.has(artist.id)}
				favoriteDisabled={favoriteBusy}
				onToggleFavorite={onToggleFavorite}
				onRename={() => setRenameOpen(true)}
			/>
			<MediaList
				query={tracks}
				testID="artist-tracks"
				onPressItem={(item) => onPressTrack(item.id)}
				emptyTitle={t("artists.noTracks")}
				emptyTestID="artist-tracks-empty"
				errorTitle={t("artists.tracksError")}
				errorTestID="artist-tracks-error"
			/>
			{renameOpen && (
				<RenameArtistModal
					artistId={artist.id}
					initialName={artist.name}
					visible
					onClose={() => setRenameOpen(false)}
				/>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	header: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
	},
	headerButton: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	headerTitle: { fontSize: 13, fontWeight: "600", letterSpacing: 0.5 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
	hero: { flexDirection: "row", alignItems: "center" },
	heroInfo: { flex: 1 },
	name: { fontSize: 24, fontWeight: "700" },
	heroActions: { flexDirection: "row", flexWrap: "wrap", alignItems: "center" },
	renameButton: {
		minHeight: 44,
		flexDirection: "row",
		alignItems: "center",
		gap: 6,
		borderWidth: 1,
	},
	renameLabel: { fontSize: 14, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

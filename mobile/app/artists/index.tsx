import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import {
	ActivityIndicator,
	Alert,
	FlatList,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import {
	useFavoriteArtistIds,
	useToggleArtistFavorite,
} from "../../src/api/favorites";
import { type ArtistEntry, useMediaArtists } from "../../src/api/metadata";
import { ArtistCover } from "../../src/components/ArtistCover";
import { ArtistFavoriteButton } from "../../src/components/ArtistFavoriteButton";
import { AuthGate } from "../../src/components/AuthGate";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import { InlineError } from "../../src/components/InlineError";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

// Deep link может открыть список первым — назад ведёт в библиотеку.
function closeArtists(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/library");
}

function ArtistsHeader() {
	const { colors } = useTheme();
	return (
		<View style={styles.header}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={closeArtists}
				testID="artists-back"
				hitSlop={8}
				style={({ pressed }) => [
					styles.headerButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<Text style={[styles.headerTitle, { color: colors.text }]}>
				{t("artists.title")}
			</Text>
			<View style={styles.headerButton} />
		</View>
	);
}

function ArtistRow({
	artist,
	favorite,
	favoriteDisabled,
	onOpen,
	onToggleFavorite,
}: {
	artist: ArtistEntry;
	favorite: boolean;
	favoriteDisabled: boolean;
	onOpen: () => void;
	onToggleFavorite: () => void;
}) {
	const { colors, radii, spacing } = useTheme();
	return (
		<View
			style={[
				styles.row,
				{
					borderColor: colors.border,
					backgroundColor: colors.surface,
					borderRadius: radii.md,
				},
			]}
		>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={artist.name}
				onPress={onOpen}
				testID={`artist-row-${artist.id}`}
				style={({ pressed }) => [
					styles.openZone,
					{ gap: spacing.md, padding: spacing.sm },
					pressed && styles.pressed,
				]}
			>
				<ArtistCover artist={artist} size={56} decorative />
				<Text numberOfLines={2} style={[styles.name, { color: colors.text }]}>
					{artist.name}
				</Text>
			</Pressable>
			<ArtistFavoriteButton
				artistName={artist.name}
				active={favorite}
				disabled={favoriteDisabled}
				testID={`artist-favorite-${artist.id}`}
				onPress={onToggleFavorite}
			/>
		</View>
	);
}

export default function ArtistsScreen() {
	return (
		<AuthGate>
			<ArtistsContent />
		</AuthGate>
	);
}

function ArtistsContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const artists = useMediaArtists();
	const favorites = useFavoriteArtistIds();
	const toggleFavorite = useToggleArtistFavorite();
	const items = artists.data ?? [];
	const favoriteIds = favorites.data ?? new Set<number>();
	const favoriteBusy =
		favorites.isPending || favorites.isFetching || toggleFavorite.isPending;

	const onToggleFavorite = (artist: ArtistEntry) => {
		toggleFavorite.mutate(
			{ artistId: artist.id, favorite: favoriteIds.has(artist.id) },
			{ onError: () => Alert.alert(t("artists.favoriteError")) },
		);
	};

	const header = <ArtistsHeader />;

	if (artists.isPending) {
		return (
			<Screen testID="artists-screen" edges={["top", "bottom"]}>
				{header}
				<View style={styles.center}>
					<ActivityIndicator color={colors.accent} />
				</View>
			</Screen>
		);
	}

	// Полный ErrorState — только когда показать нечего. Ошибка фонового
	// рефетча при уже загруженном списке уходит в inline-баннер.
	if (artists.isError && artists.data === undefined) {
		return (
			<Screen testID="artists-screen" edges={["top", "bottom"]}>
				{header}
				<ErrorState
					title={t("artists.loadError")}
					onRetry={() => void artists.refetch()}
					retryTestID="artists-retry"
					testID="artists-error"
				/>
			</Screen>
		);
	}

	const inlineError = artists.isError ? (
		<InlineError
			message={t("artists.loadError")}
			onRetry={() => void artists.refetch()}
			testID="artists-inline-error"
			retryTestID="artists-inline-retry"
		/>
	) : null;

	if (items.length === 0) {
		return (
			<Screen testID="artists-screen" edges={["top", "bottom"]}>
				{header}
				{inlineError}
				<EmptyState
					icon="people-outline"
					title={t("artists.empty")}
					description={t("artists.emptyHint")}
					testID="artists-empty"
				/>
			</Screen>
		);
	}

	return (
		<Screen testID="artists-screen" edges={["top", "bottom"]}>
			{header}
			{inlineError}
			<FlatList
				testID="artists-list"
				data={items}
				keyExtractor={(artist) => String(artist.id)}
				style={styles.fill}
				contentContainerStyle={{ gap: spacing.sm, paddingBottom: spacing.xl }}
				refreshing={artists.isRefetching}
				onRefresh={() => void artists.refetch()}
				renderItem={({ item }) => (
					<ArtistRow
						artist={item}
						favorite={favoriteIds.has(item.id)}
						favoriteDisabled={favoriteBusy}
						onOpen={() => router.push(`/artists/${item.id}`)}
						onToggleFavorite={() => onToggleFavorite(item)}
					/>
				)}
			/>
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
	headerTitle: { fontSize: 18, fontWeight: "700" },
	fill: { flex: 1 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
	row: {
		flexDirection: "row",
		alignItems: "center",
		borderWidth: 1,
		paddingRight: 4,
	},
	openZone: { flex: 1, flexDirection: "row", alignItems: "center" },
	name: { flex: 1, fontSize: 16, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

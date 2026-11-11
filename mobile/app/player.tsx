import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import { useState } from "react";
import {
	ActivityIndicator,
	Alert,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import {
	useFavoriteAudioIds,
	useToggleAudioFavorite,
} from "../src/api/favorites";
import { AddToCollectionSheet } from "../src/components/AddToCollectionSheet";
import { ArtistLinks } from "../src/components/ArtistLinks";
import { AuthGate } from "../src/components/AuthGate";
import { DownloadButton } from "../src/components/DownloadButton";
import { EmptyState } from "../src/components/EmptyState";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { AudioCover } from "../src/player/AudioCover";
import { AudioPlayerControls } from "../src/player/AudioPlayerControls";
import { useAudioActions, useAudioState } from "../src/player/AudioProvider";
import { AudioQueueSheet } from "../src/player/AudioQueueSheet";
import { useTheme } from "../src/theme/ThemeProvider";

// Deep link может открыть плеер без истории: возвращаемся на вкладку аудио.
function closePlayer(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/audio");
}

function CloseButton() {
	const { colors } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={t("audio.player.dismiss")}
			onPress={closePlayer}
			testID="audio-player-close"
			hitSlop={8}
			style={({ pressed }) => [styles.close, pressed && styles.pressed]}
		>
			<Ionicons name="chevron-down" size={24} color={colors.text} />
		</Pressable>
	);
}

export default function AudioPlayerScreen() {
	return (
		<AuthGate>
			<AudioPlayerContent />
		</AuthGate>
	);
}

function AudioPlayerContent() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const {
		current,
		queue,
		index,
		displayPlaying,
		currentTime,
		duration,
		shuffle,
		repeat,
		error,
		loading,
		buffering,
		rate,
	} = useAudioState();
	const {
		seek,
		toggle,
		next,
		previous,
		cycleRate,
		toggleShuffle,
		cycleRepeat,
	} = useAudioActions();
	const favorites = useFavoriteAudioIds();
	const toggleFavorite = useToggleAudioFavorite();
	const [queueOpen, setQueueOpen] = useState(false);
	const [collectionOpen, setCollectionOpen] = useState(false);

	const closeButton = <CloseButton />;
	if (current === null) {
		return (
			<Screen testID="audio-player" edges={["top", "bottom"]}>
				{closeButton}
				<EmptyState
					icon="musical-notes-outline"
					title={t("audio.player.empty")}
					description={t("audio.player.emptyHint")}
					testID="audio-player-empty"
				/>
			</Screen>
		);
	}

	const isFavorite = favorites.data?.has(current.id) ?? false;
	const favoriteBusy = favorites.isFetching || toggleFavorite.isPending;
	const bufferingNow = loading || buffering;

	const onToggleFavorite = () => {
		toggleFavorite.mutate(
			{ mediaId: current.id, favorite: isFavorite, media: current },
			{ onError: () => Alert.alert(t("audio.player.favoriteError")) },
		);
	};

	return (
		<Screen scroll testID="audio-player" edges={["top", "bottom"]}>
			<View style={styles.header}>
				{closeButton}
				<Text style={[styles.headerTitle, { color: colors.textMuted }]}>
					{t("audio.player.nowPlaying")}
				</Text>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("audio.lyrics.open")}
					onPress={() => router.push(`/audio/${current.id}`)}
					testID="audio-player-lyrics"
					hitSlop={8}
					style={({ pressed }) => [styles.close, pressed && styles.pressed]}
				>
					<Ionicons
						name="document-text-outline"
						size={24}
						color={colors.text}
					/>
				</Pressable>
			</View>
			<View style={styles.coverWrap}>
				<AudioCover media={current} size={260} testID="audio-player-cover" />
			</View>
			<View style={[styles.info, { gap: spacing.xs }]}>
				<Text
					testID="audio-player-title"
					numberOfLines={2}
					style={[styles.title, { color: colors.text }]}
				>
					{current.title}
				</Text>
				<ArtistLinks
					artists={current.artists}
					emptyLabel={t("audio.player.unknownArtist")}
					style={styles.artist}
					testID="audio-player-artist"
					align="center"
				/>
				<View style={[styles.metaRow, { gap: spacing.sm }]}>
					<Text
						testID="audio-player-index"
						style={[styles.meta, { color: colors.textMuted }]}
					>
						{`${index + 1}/${queue.length}`}
					</Text>
					{bufferingNow && (
						<View style={[styles.metaRow, { gap: spacing.xs }]}>
							<ActivityIndicator size="small" color={colors.accent} />
							<Text
								testID="audio-player-buffering"
								accessibilityLiveRegion="polite"
								style={[styles.meta, { color: colors.textMuted }]}
							>
								{t("audio.player.buffering")}
							</Text>
						</View>
					)}
				</View>
				{error !== null && (
					<Text
						accessibilityRole="alert"
						accessibilityLiveRegion="polite"
						testID="audio-player-error"
						style={[styles.error, { color: colors.danger }]}
					>
						{error}
					</Text>
				)}
			</View>
			<DownloadButton media={current} testID="audio-player-download" />
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("collections.addButton")}
				onPress={() => setCollectionOpen(true)}
				testID="audio-player-add-collection"
				style={({ pressed }) => [
					styles.collectionButton,
					{
						borderColor: colors.borderStrong,
						backgroundColor: colors.surface,
						borderRadius: radii.pill,
						gap: spacing.xs,
						paddingHorizontal: spacing.md,
					},
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="folder-open-outline" size={18} color={colors.accent} />
				<Text style={[styles.collectionLabel, { color: colors.accent }]}>
					{t("collections.addButton")}
				</Text>
			</Pressable>
			<AudioPlayerControls
				position={currentTime}
				duration={duration}
				displayPlaying={displayPlaying}
				rate={rate}
				shuffle={shuffle}
				repeat={repeat}
				favorite={isFavorite}
				favoriteDisabled={favoriteBusy}
				onSeekTo={seek}
				onToggle={toggle}
				onNext={next}
				onPrevious={previous}
				onCycleRate={cycleRate}
				onToggleShuffle={toggleShuffle}
				onCycleRepeat={cycleRepeat}
				onToggleFavorite={onToggleFavorite}
				onOpenQueue={() => setQueueOpen(true)}
			/>
			{collectionOpen && (
				<AddToCollectionSheet
					visible
					mediaId={current.id}
					type="audio"
					onClose={() => setCollectionOpen(false)}
				/>
			)}
			<AudioQueueSheet
				visible={queueOpen}
				onClose={() => setQueueOpen(false)}
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
	headerTitle: { fontSize: 13, fontWeight: "600", letterSpacing: 0.5 },
	close: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	coverWrap: { alignItems: "center", paddingVertical: 8 },
	info: { alignItems: "center" },
	title: { fontSize: 24, fontWeight: "700", textAlign: "center" },
	artist: { fontSize: 15 },
	metaRow: { flexDirection: "row", alignItems: "center" },
	meta: { fontSize: 13, fontVariant: ["tabular-nums"] },
	error: { fontSize: 14, textAlign: "center" },
	collectionButton: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		alignSelf: "center",
		minHeight: 44,
		borderWidth: 1,
	},
	collectionLabel: { fontSize: 14, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

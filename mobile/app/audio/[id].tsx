import Ionicons from "@expo/vector-icons/Ionicons";
import { ApiError, type Lyrics, type SaveLyricsInput } from "@flux/shared";
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
import { useLyrics, useSaveLyrics } from "../../src/api/lyrics";
import { useMedia } from "../../src/api/media";
import { useSession } from "../../src/auth/session";
import { ArtistLinks } from "../../src/components/ArtistLinks";
import { AuthGate } from "../../src/components/AuthGate";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import {
	type LyricsDraft,
	LyricsEditor,
} from "../../src/components/LyricsEditor";
import { LyricsView } from "../../src/components/LyricsView";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import {
	defaultLyricsTab,
	hasLyricsText,
	hasTranslation,
	type LyricsTab,
	parseMediaIdParam,
	resolveLyricsTab,
} from "../../src/lyrics/lyricsView";
import { AudioCover } from "../../src/player/AudioCover";
import { useAudioState } from "../../src/player/AudioProvider";
import { useTheme } from "../../src/theme/ThemeProvider";

// Deep link может открыть текст первым — тогда назад ведёт на вкладку аудио.
function closeLyrics(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/audio");
}

function draftFrom(lyrics: Lyrics | null | undefined): LyricsDraft {
	return {
		lyricsText: lyrics?.lyrics_text ?? "",
		translation: lyrics?.translation ?? "",
		syncData: lyrics?.sync_data ?? "",
		source: lyrics?.source ?? "user",
	};
}

function HeaderButton({
	icon,
	label,
	onPress,
	testID,
}: {
	icon: "chevron-back" | "create-outline";
	label: string;
	onPress: () => void;
	testID: string;
}) {
	const { colors } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			onPress={onPress}
			testID={testID}
			hitSlop={8}
			style={({ pressed }) => [styles.headerButton, pressed && styles.pressed]}
		>
			<Ionicons name={icon} size={24} color={colors.text} />
		</Pressable>
	);
}

function TabButton({
	label,
	selected,
	onPress,
	testID,
}: {
	label: string;
	selected: boolean;
	onPress: () => void;
	testID: string;
}) {
	const { colors, spacing } = useTheme();
	return (
		<Pressable
			accessibilityRole="tab"
			accessibilityLabel={label}
			accessibilityState={{ selected }}
			onPress={onPress}
			testID={testID}
			style={({ pressed }) => [
				styles.tab,
				{
					borderBottomColor: selected ? colors.accent : "transparent",
					paddingHorizontal: spacing.md,
				},
				pressed && styles.pressed,
			]}
		>
			<Text
				style={[
					styles.tabLabel,
					{
						color: selected ? colors.accent : colors.textMuted,
						fontWeight: selected ? "700" : "600",
					},
				]}
			>
				{label}
			</Text>
		</Pressable>
	);
}

function LyricsHeader({
	isAdmin,
	canEdit,
	onEdit,
}: {
	isAdmin: boolean;
	canEdit: boolean;
	onEdit: () => void;
}) {
	const { colors } = useTheme();
	return (
		<View style={styles.header}>
			<HeaderButton
				icon="chevron-back"
				label={t("common.back")}
				onPress={closeLyrics}
				testID="audio-lyrics-back"
			/>
			<Text style={[styles.headerTitle, { color: colors.textMuted }]}>
				{t("audio.lyrics.title")}
			</Text>
			{isAdmin ? (
				<HeaderButton
					icon="create-outline"
					label={canEdit ? t("audio.lyrics.edit") : t("audio.lyrics.add")}
					onPress={onEdit}
					testID="audio-lyrics-edit"
				/>
			) : (
				<View style={styles.headerButton} />
			)}
		</View>
	);
}

function LyricsTabs({
	activeTab,
	translation,
	onChange,
}: {
	activeTab: LyricsTab;
	translation: string;
	onChange: (tab: LyricsTab) => void;
}) {
	const { colors } = useTheme();
	return (
		<View
			accessibilityRole="tablist"
			style={[styles.tabs, { borderBottomColor: colors.border }]}
		>
			<TabButton
				label={t("audio.lyrics.tabLyrics")}
				selected={activeTab === "lyrics"}
				onPress={() => onChange("lyrics")}
				testID="audio-lyrics-tab-lyrics"
			/>
			{hasTranslation(translation) && (
				<TabButton
					label={t("audio.lyrics.tabTranslation")}
					selected={activeTab === "translation"}
					onPress={() => onChange("translation")}
					testID="audio-lyrics-tab-translation"
				/>
			)}
		</View>
	);
}

export default function AudioLyricsScreen() {
	return (
		<AuthGate>
			<AudioLyricsContent />
		</AuthGate>
	);
}

function AudioLyricsContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const mediaId = parseMediaIdParam(params.id);
	const media = useMedia(mediaId ?? 0, mediaId !== null);
	const lyrics = useLyrics(mediaId ?? 0, mediaId !== null);
	const save = useSaveLyrics(mediaId ?? 0);
	const session = useSession();
	const { current, currentTime } = useAudioState();
	const [tab, setTab] = useState<LyricsTab | null>(null);
	const [editing, setEditing] = useState(false);

	const track = media.data;
	const isAdmin = session.data?.is_admin === true;
	const translation = lyrics.data?.translation ?? "";
	const hasText = useMemo(
		() =>
			hasLyricsText(
				lyrics.data?.lyrics_text ?? "",
				lyrics.data?.sync_data ?? "",
			),
		[lyrics.data?.lyrics_text, lyrics.data?.sync_data],
	);
	// null — пользователь ещё не выбирал вкладку: стартуем с перевода,
	// если текста нет, а перевод есть.
	const activeTab =
		tab === null
			? defaultLyricsTab(hasText, translation)
			: resolveLyricsTab(tab, translation);
	const isCurrentTrack = mediaId !== null && current?.id === mediaId;
	// «Добавить» доступно админу и без успешного fetch (пустой/ошибочный
	// ответ), «Редактировать» — только когда существующие данные загружены.
	const canEdit = isAdmin && lyrics.isSuccess && lyrics.data !== null;
	// 404 медиа — это «трека нет», а не сетевая ошибка с retry.
	const mediaNotFound =
		media.error instanceof ApiError && media.error.status === 404;

	const saveLyrics = (input: SaveLyricsInput) => {
		save.mutate(input, {
			onSuccess: () => setEditing(false),
			onError: () => Alert.alert(t("audio.lyrics.saveError")),
		});
	};

	const header = (
		<LyricsHeader
			// Редактор имеет смысл только для загруженного трека; статус
			// lyrics (success) для «Добавить» не требуется.
			isAdmin={isAdmin && track !== undefined}
			canEdit={canEdit}
			onEdit={() => setEditing(true)}
		/>
	);

	if (mediaId === null) {
		return (
			<Screen testID="audio-lyrics" edges={["top", "bottom"]}>
				{header}
				<EmptyState
					icon="musical-notes-outline"
					title={t("audio.lyrics.notFound")}
					description={t("audio.lyrics.notFoundHint")}
					testID="audio-lyrics-not-found"
				/>
			</Screen>
		);
	}

	if (media.isPending) {
		return (
			<Screen testID="audio-lyrics" edges={["top", "bottom"]}>
				{header}
				<View style={styles.center}>
					<ActivityIndicator color={colors.accent} />
				</View>
			</Screen>
		);
	}

	if (mediaNotFound) {
		return (
			<Screen testID="audio-lyrics" edges={["top", "bottom"]}>
				{header}
				<EmptyState
					icon="musical-notes-outline"
					title={t("audio.lyrics.notFound")}
					description={t("audio.lyrics.notFoundHint")}
					testID="audio-lyrics-not-found"
				/>
			</Screen>
		);
	}

	if (media.isError || track === undefined) {
		return (
			<Screen testID="audio-lyrics" edges={["top", "bottom"]}>
				{header}
				<ErrorState
					title={t("audio.loadError")}
					onRetry={() => void media.refetch()}
					retryTestID="audio-lyrics-retry"
					testID="audio-lyrics-error"
				/>
			</Screen>
		);
	}

	return (
		<Screen testID="audio-lyrics" edges={["top", "bottom"]}>
			{header}
			<View style={[styles.track, { gap: spacing.sm }]}>
				<AudioCover media={track} size={72} testID="audio-lyrics-cover" />
				<View style={styles.trackText}>
					<Text
						testID="audio-lyrics-title"
						numberOfLines={2}
						style={[styles.title, { color: colors.text }]}
					>
						{track.title}
					</Text>
					<ArtistLinks
						artists={track.artists}
						emptyLabel={t("audio.player.unknownArtist")}
						style={styles.artist}
						testID="audio-lyrics-artist"
					/>
				</View>
			</View>
			{current !== null && !isCurrentTrack && (
				<Text
					testID="audio-lyrics-other-track"
					style={[styles.notice, { color: colors.textMuted }]}
				>
					{t("audio.lyrics.notCurrent")}
				</Text>
			)}
			<LyricsTabs
				activeTab={activeTab}
				translation={translation}
				onChange={setTab}
			/>
			<View style={styles.content}>
				{lyrics.isPending ? (
					<View style={styles.center}>
						<ActivityIndicator color={colors.accent} />
					</View>
				) : lyrics.isError ? (
					<ErrorState
						title={t("audio.lyrics.loadError")}
						onRetry={() => void lyrics.refetch()}
						retryTestID="audio-lyrics-lyrics-retry"
						testID="audio-lyrics-lyrics-error"
					/>
				) : (
					<LyricsView
						lyrics={lyrics.data ?? null}
						tab={activeTab}
						position={currentTime}
						isCurrentTrack={isCurrentTrack}
						onAdd={isAdmin ? () => setEditing(true) : undefined}
					/>
				)}
			</View>
			{editing && (
				<LyricsEditor
					initial={draftFrom(lyrics.data)}
					hasExisting={lyrics.data !== null && lyrics.data !== undefined}
					saving={save.isPending}
					onCancel={() => setEditing(false)}
					onSave={saveLyrics}
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
	track: { flexDirection: "row", alignItems: "center" },
	trackText: { flex: 1 },
	title: { fontSize: 20, fontWeight: "700" },
	artist: { fontSize: 14 },
	notice: { fontSize: 13, lineHeight: 18 },
	tabs: { flexDirection: "row", borderBottomWidth: 1 },
	tab: {
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
		borderBottomWidth: 2,
	},
	tabLabel: { fontSize: 15 },
	content: { flex: 1 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
	pressed: { opacity: 0.7 },
});

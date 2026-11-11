import Ionicons from "@expo/vector-icons/Ionicons";
import { ApiError } from "@flux/shared";
import { router, useLocalSearchParams } from "expo-router";
import type { ComponentProps } from "react";
import { useState } from "react";
import {
	ActivityIndicator,
	Alert,
	Linking,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import {
	type ExtractFailure,
	type ExtractPhase,
	useExtractAudio,
} from "../../src/api/extract";
import {
	useFavoriteVideoIds,
	useToggleVideoFavorite,
} from "../../src/api/favorites";
import { useDeleteMedia, useMedia } from "../../src/api/media";
import { useSession } from "../../src/auth/session";
import { AddToCollectionSheet } from "../../src/components/AddToCollectionSheet";
import { AuthGate } from "../../src/components/AuthGate";
import { ChangeCoverSheet } from "../../src/components/ChangeCoverSheet";
import { DownloadButton } from "../../src/components/DownloadButton";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import { Screen } from "../../src/components/Screen";
import { VideoMeta } from "../../src/components/VideoMeta";
import { t, useLanguage } from "../../src/i18n";
import { isHttpSourceUrl } from "../../src/media/source";
import { VideoPlayer } from "../../src/player/VideoPlayer";
import { useTheme } from "../../src/theme/ThemeProvider";
import { isTV, tvCapabilities } from "../../src/tv/profile";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

// Из stack-экрана деталей назад всегда есть история (список), но deep link
// может открыть экран первым — тогда возвращаемся на вкладку видео.
function goBackToVideoList(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/video");
}

function BackButton() {
	const { colors } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={t("common.back")}
			onPress={goBackToVideoList}
			testID="video-detail-back"
			hitSlop={8}
			style={({ pressed }) => [styles.back, pressed && styles.pressed]}
		>
			<Ionicons name="chevron-back" size={20} color={colors.accent} />
			<Text style={[styles.backLabel, { color: colors.accent }]}>
				{t("common.back")}
			</Text>
		</Pressable>
	);
}

interface ActionButtonProps {
	icon: IoniconName;
	label: string;
	onPress: () => void;
	testID: string;
	disabled?: boolean;
	danger?: boolean;
	selected?: boolean;
}

function ActionButton({
	icon,
	label,
	onPress,
	testID,
	disabled = false,
	danger = false,
	selected,
}: ActionButtonProps) {
	const { colors, radii, spacing } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			accessibilityState={{ disabled, selected }}
			disabled={disabled}
			onPress={onPress}
			testID={testID}
			hitSlop={4}
			style={({ pressed }) => [
				styles.actionButton,
				{
					backgroundColor: colors.surface,
					borderColor: danger ? colors.danger : colors.borderStrong,
					borderRadius: radii.sm,
					gap: spacing.xs,
					paddingHorizontal: spacing.md,
					paddingVertical: spacing.sm,
				},
				disabled && styles.disabled,
				pressed && styles.pressed,
			]}
		>
			<Ionicons
				name={icon}
				size={18}
				color={danger ? colors.danger : colors.text}
			/>
			<Text
				style={[
					styles.actionLabel,
					{ color: danger ? colors.danger : colors.text },
				]}
			>
				{label}
			</Text>
		</Pressable>
	);
}

function extractPhaseLabel(phase: ExtractPhase | null): string {
	if (phase === "processing") {
		return t("video.extractProcessing");
	}
	if (phase === "queued") {
		return t("video.extractQueued");
	}
	return t("video.extractStarting");
}

function extractFailureLabel(failure: ExtractFailure): string {
	switch (failure.kind) {
		case "conflict":
			return t("video.extractAlready");
		case "unavailable":
			return t("video.extractUnavailable");
		case "rateLimited":
			return t("video.extractRateLimited");
		default:
			return t("video.extractError");
	}
}

// Извлечение доступно только админу (backend requireAdmin). Компонент
// монтируется в admin-ветке, поэтому хук не крутится у обычных зрителей.
function ExtractAudioControl({ mediaId }: { mediaId: number }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const extract = useExtractAudio(mediaId);
	const cancelLabel = t("common.cancel");

	const run = async () => {
		const result = await extract.start();
		if (result === null) {
			// Ошибка уже лежит в extract.failure и отрисована под кнопкой.
			return;
		}
		Alert.alert(
			result.alreadyExtracted
				? t("video.extractAlreadyTitle")
				: t("video.extractDoneTitle"),
			result.alreadyExtracted
				? t("video.extractAlready")
				: t("video.extractDone"),
		);
	};

	const confirm = () => {
		Alert.alert(t("video.extractTitle"), t("video.extractConfirm"), [
			{ text: cancelLabel, style: "cancel" },
			{
				text: t("video.extractAction"),
				onPress: () => {
					void run();
				},
			},
		]);
	};

	return (
		<View
			style={[styles.extractControl, { gap: spacing.sm }]}
			testID="video-detail-extract-control"
		>
			<ActionButton
				icon="musical-notes-outline"
				label={
					extract.isExtracting
						? t("video.extractProcessing")
						: t("video.extract")
				}
				onPress={confirm}
				testID="video-detail-extract"
				disabled={extract.isExtracting}
			/>
			{extract.isExtracting && (
				<View
					style={[styles.extractStatus, { gap: spacing.sm }]}
					testID="video-detail-extract-status"
				>
					<ActivityIndicator size="small" color={colors.accent} />
					<Text
						accessibilityLiveRegion="polite"
						style={[styles.extractStatusText, { color: colors.textMuted }]}
					>
						{extractPhaseLabel(extract.phase)}
					</Text>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={cancelLabel}
						onPress={() => {
							void extract.cancel();
						}}
						testID="video-detail-extract-cancel"
						hitSlop={4}
						style={styles.inlineRetry}
					>
						<Text style={[styles.actionLabel, { color: colors.danger }]}>
							{cancelLabel}
						</Text>
					</Pressable>
				</View>
			)}
			{extract.failure !== null && !extract.isExtracting && (
				<Text
					accessibilityRole="alert"
					accessibilityLiveRegion="polite"
					testID="video-detail-extract-error"
					style={[styles.extractError, { color: colors.danger }]}
				>
					{extractFailureLabel(extract.failure)}
				</Text>
			)}
		</View>
	);
}

function LoadingState() {
	const { colors, spacing } = useTheme();
	return (
		<View style={[styles.centered, { gap: spacing.sm }]}>
			<ActivityIndicator color={colors.accent} />
			<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
		</View>
	);
}

function NotFoundScreen() {
	return (
		<Screen testID="video-detail-screen">
			<BackButton />
			<EmptyState
				icon="videocam-off-outline"
				title={t("video.notFound")}
				description={t("video.notFoundDescription")}
				testID="video-detail-not-found"
			/>
		</Screen>
	);
}

// AuthGate монтируется до запросов деталей: deep link без сессии уходит на
// /login, а не показывает 401-ErrorState. Контент — отдельный компонент,
// чтобы useMedia/favorites не запускались до проверки сессии.
export default function VideoDetailScreen() {
	return (
		<AuthGate>
			<VideoDetailContent />
		</AuthGate>
	);
}

function VideoDetailContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const rawId = Array.isArray(params.id) ? params.id[0] : params.id;
	const mediaId = rawId === undefined ? Number.NaN : Number(rawId);
	const valid = Number.isInteger(mediaId) && mediaId > 0;

	const media = useMedia(valid ? mediaId : 0, valid);
	const session = useSession();
	const favorites = useFavoriteVideoIds();
	const toggleFavorite = useToggleVideoFavorite();
	const removeMedia = useDeleteMedia();
	const [collectionSheetOpen, setCollectionSheetOpen] = useState(false);
	const [coverSheetOpen, setCoverSheetOpen] = useState(false);
	// После PUT обложки URL не меняется, поэтому постер получает версию и
	// перезагружает картинку в обход кэша expo-image.
	const [coverVersion, setCoverVersion] = useState(0);

	if (!valid) {
		return <NotFoundScreen />;
	}

	if (media.isPending) {
		return (
			<Screen testID="video-detail-screen">
				<BackButton />
				<LoadingState />
			</Screen>
		);
	}

	// Данные не должны исчезать из-за ошибки фонового refetch: ErrorState
	// показываем только пока данных ещё нет (первый запрос).
	if (media.data === undefined) {
		const notFound =
			media.error instanceof ApiError && media.error.status === 404;
		if (notFound) {
			return <NotFoundScreen />;
		}
		return (
			<Screen testID="video-detail-screen">
				<BackButton />
				<ErrorState
					title={t("video.loadError")}
					onRetry={() => void media.refetch()}
					testID="video-detail-error"
				/>
			</Screen>
		);
	}

	const item = media.data;
	// audioId в video-route — не видео: показываем 404, а не экран видео.
	if (item.type !== "video") {
		return <NotFoundScreen />;
	}
	const artists = item.artists.map((artist) => artist.name).join(", ");
	const isFavorite = favorites.data?.has(item.id) ?? false;
	const favoriteBusy = favorites.isFetching || toggleFavorite.isPending;
	const sourceUrl = item.source_url.trim();

	const toggle = () => {
		toggleFavorite.mutate(
			{ mediaId: item.id, favorite: isFavorite, media: item },
			{ onError: () => Alert.alert(t("video.favoriteError")) },
		);
	};

	const openSource = () => {
		void Linking.openURL(sourceUrl).catch(() => {
			Alert.alert(t("video.sourceError"));
		});
	};

	const confirmDelete = () => {
		Alert.alert(t("video.deleteTitle"), t("video.deleteConfirm"), [
			{ text: t("common.cancel"), style: "cancel" },
			{
				text: t("video.delete"),
				style: "destructive",
				onPress: () => {
					removeMedia.mutate(item.id, {
						onSuccess: goBackToVideoList,
						onError: () => Alert.alert(t("video.deleteError")),
					});
				},
			},
		]);
	};

	return (
		<Screen scroll testID="video-detail-screen">
			<BackButton />
			<VideoPlayer key={item.id} media={item} coverVersion={coverVersion} />
			<View style={{ gap: spacing.xs }}>
				<Text
					testID="video-detail-title"
					style={[styles.title, { color: colors.text }]}
				>
					{item.title}
				</Text>
				{artists !== "" && (
					<Text style={[styles.artists, { color: colors.textMuted }]}>
						{artists}
					</Text>
				)}
			</View>
			<VideoMeta media={item} />
			{item.description !== "" && (
				<Text style={[styles.description, { color: colors.text }]}>
					{item.description}
				</Text>
			)}
			{media.isError && (
				<View
					style={[styles.inlineError, { gap: spacing.sm }]}
					testID="video-detail-inline-error"
				>
					<Text style={[styles.inlineErrorText, { color: colors.danger }]}>
						{t("video.loadError")}
					</Text>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("common.retry")}
						onPress={() => void media.refetch()}
						testID="video-detail-inline-retry"
						style={styles.inlineRetry}
					>
						<Text style={[styles.actionLabel, { color: colors.accent }]}>
							{t("common.retry")}
						</Text>
					</Pressable>
				</View>
			)}
			<View style={[styles.actions, { gap: spacing.sm }]}>
				<ActionButton
					icon={isFavorite ? "heart" : "heart-outline"}
					label={isFavorite ? t("media.unfavorite") : t("media.favorite")}
					onPress={toggle}
					testID={`video-detail-favorite-${
						favoriteBusy ? "disabled" : isFavorite ? "on" : "off"
					}`}
					disabled={favoriteBusy}
					selected={isFavorite}
					danger={isFavorite}
				/>
				{tvCapabilities.canDownload && (
					<DownloadButton media={item} testID="video-detail-download" />
				)}
				{tvCapabilities.canManageCollections && (
					<ActionButton
						icon="folder-open-outline"
						label={t("video.addToCollection")}
						onPress={() => setCollectionSheetOpen(true)}
						testID="video-detail-add-collection"
					/>
				)}
				{isHttpSourceUrl(sourceUrl) && (
					<ActionButton
						icon="link-outline"
						label={t("video.sourceLink")}
						onPress={openSource}
						testID="video-detail-source"
					/>
				)}
				{!isTV && session.data?.is_admin === true && (
					<>
						<ExtractAudioControl mediaId={item.id} />
						<ActionButton
							icon="create-outline"
							label={t("metadata.edit")}
							onPress={() => router.push(`/media/${item.id}/edit`)}
							testID="video-detail-edit"
						/>
						<ActionButton
							icon="image-outline"
							label={t("cover.change")}
							onPress={() => setCoverSheetOpen(true)}
							testID="video-detail-cover"
						/>
						<ActionButton
							icon="trash-outline"
							label={t("video.delete")}
							onPress={confirmDelete}
							testID="video-detail-delete"
							disabled={removeMedia.isPending}
							danger
						/>
					</>
				)}
			</View>
			{collectionSheetOpen && (
				<AddToCollectionSheet
					visible
					mediaId={item.id}
					type="video"
					onClose={() => setCollectionSheetOpen(false)}
				/>
			)}
			{coverSheetOpen && (
				<ChangeCoverSheet
					visible
					media={item}
					onClose={() => setCoverSheetOpen(false)}
					onUploaded={() => setCoverVersion((current) => current + 1)}
				/>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	centered: { flex: 1, alignItems: "center", justifyContent: "center" },
	back: {
		flexDirection: "row",
		alignItems: "center",
		alignSelf: "flex-start",
		minHeight: 44,
	},
	backLabel: { fontSize: 15, fontWeight: "600" },
	title: { fontSize: 24, fontWeight: "700" },
	artists: { fontSize: 15 },
	description: { fontSize: 15, lineHeight: 22 },
	inlineError: { flexDirection: "row", alignItems: "center", flexWrap: "wrap" },
	inlineErrorText: { flexShrink: 1, fontSize: 14 },
	inlineRetry: {
		minHeight: 44,
		justifyContent: "center",
		paddingHorizontal: 8,
	},
	actions: { flexDirection: "row", flexWrap: "wrap" },
	extractControl: { alignItems: "flex-start" },
	extractStatus: {
		flexDirection: "row",
		alignItems: "center",
		flexWrap: "wrap",
		minHeight: 44,
	},
	extractStatusText: { fontSize: 14 },
	extractError: { fontSize: 14 },
	actionButton: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		minHeight: 44,
		borderWidth: 1,
	},
	actionLabel: { fontSize: 14, fontWeight: "600" },
	disabled: { opacity: 0.5 },
	pressed: { opacity: 0.7 },
});

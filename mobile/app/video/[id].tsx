import Ionicons from "@expo/vector-icons/Ionicons";
import { ApiError, type Media } from "@flux/shared";
import { Image } from "expo-image";
import { router, useLocalSearchParams } from "expo-router";
import type { ComponentProps } from "react";
import { useEffect, useState } from "react";
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
	useFavoriteVideoIds,
	useToggleVideoFavorite,
} from "../../src/api/favorites";
import { useDeleteMedia, useMedia } from "../../src/api/media";
import { useSession } from "../../src/auth/session";
import { AddToCollectionSheet } from "../../src/components/AddToCollectionSheet";
import { AuthGate } from "../../src/components/AuthGate";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import { Screen } from "../../src/components/Screen";
import { VideoMeta } from "../../src/components/VideoMeta";
import { t, useLanguage } from "../../src/i18n";
import {
	coverPath,
	imageSource,
	isHttpSourceUrl,
	thumbPath,
} from "../../src/media/source";
import { useTheme } from "../../src/theme/ThemeProvider";

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

// Постер берёт авторизованный source из imageSource: media.cover_url уже
// содержит /api и без заголовков отдал бы 401. Cover используем, только
// если он реально есть, иначе — thumbnail.
function VideoPoster({ media }: { media: Media }) {
	const { colors, radii } = useTheme();
	// Cover есть не у всех видео, а файл cover мог быть удалён отдельно:
	// при ошибке загрузки откатываемся на thumbnail.
	const thumbnail = thumbPath(media.id);
	const [path, setPath] = useState(
		media.cover_url === "" ? thumbnail : coverPath(media.id),
	);
	const [source, setSource] = useState<Awaited<
		ReturnType<typeof imageSource>
	> | null>(null);
	// Оба варианта (cover и thumbnail) могут отсутствовать/биться: тогда
	// показываем заглушку, а не пустую surface-плашку с broken image.
	const [failed, setFailed] = useState(false);

	useEffect(() => {
		let active = true;
		imageSource(path).then(
			(next) => {
				if (active) {
					setSource(next);
				}
			},
			() => {
				if (active) {
					setSource(null);
				}
			},
		);
		return () => {
			active = false;
		};
	}, [path]);

	const aspectRatio =
		media.width > 0 && media.height > 0 ? media.width / media.height : 16 / 9;

	return (
		<View
			testID="video-detail-poster"
			style={[
				styles.poster,
				{
					aspectRatio,
					backgroundColor: colors.surfaceMuted,
					borderRadius: radii.md,
				},
			]}
		>
			{source === null || failed ? (
				<View style={styles.posterPlaceholder}>
					<Ionicons
						name="videocam-outline"
						size={40}
						color={colors.textMuted}
					/>
				</View>
			) : (
				<Image
					source={source}
					style={StyleSheet.absoluteFill}
					contentFit="cover"
					transition={150}
					accessibilityIgnoresInvertColors
					onError={() => {
						if (path !== thumbnail) {
							setFailed(false);
							setPath(thumbnail);
							return;
						}
						setFailed(true);
					}}
				/>
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
	const sourceUrl = item.source_url.trim();

	const toggle = () => {
		toggleFavorite.mutate(
			{ mediaId: item.id, favorite: isFavorite },
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
			<VideoPoster key={item.id} media={item} />
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
					testID="video-detail-favorite"
					disabled={favorites.isFetching || toggleFavorite.isPending}
					selected={isFavorite}
					danger={isFavorite}
				/>
				<ActionButton
					icon="folder-open-outline"
					label={t("video.addToCollection")}
					onPress={() => setCollectionSheetOpen(true)}
					testID="video-detail-add-collection"
				/>
				{isHttpSourceUrl(sourceUrl) && (
					<ActionButton
						icon="link-outline"
						label={t("video.sourceLink")}
						onPress={openSource}
						testID="video-detail-source"
					/>
				)}
				{session.data?.is_admin === true && (
					<ActionButton
						icon="trash-outline"
						label={t("video.delete")}
						onPress={confirmDelete}
						testID="video-detail-delete"
						disabled={removeMedia.isPending}
						danger
					/>
				)}
			</View>
			{collectionSheetOpen && (
				<AddToCollectionSheet
					visible
					mediaId={item.id}
					onClose={() => setCollectionSheetOpen(false)}
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
	poster: { width: "100%", overflow: "hidden" },
	posterPlaceholder: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
	},
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

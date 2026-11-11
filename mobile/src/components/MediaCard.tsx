import Ionicons from "@expo/vector-icons/Ionicons";
import { formatDuration } from "@flux/shared";
import { Image, type ImageProps, type ImageSource } from "expo-image";
import type { ComponentProps } from "react";
import {
	Pressable,
	type StyleProp,
	StyleSheet,
	Text,
	View,
	type ViewStyle,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { clampProgress } from "./homeRows";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

export type MediaCardVariant = "video" | "audio";

// До Task 6 (авторизованные медиа-URL) карточка принимает готовый source:
// строку URL или объект expo-image с headers. Без source показывается
// заглушка, поэтому компонент не зависит от формы Media.
export type MediaCardImageSource = string | ImageSource | null;

export interface MediaCardProps {
	title: string;
	subtitle?: string;
	/** Длительность в секундах; 0 тоже валидное значение. */
	duration?: number;
	/** Доля просмотра/прослушивания 0..1 для полосы «Продолжить». */
	progress?: number;
	badge?: string;
	variant?: MediaCardVariant;
	imageSource?: MediaCardImageSource;
	/**
	 * Обложки живут по неизменному URL, поэтому им нужен cachePolicy="none",
	 * чтобы после PUT не показывать старую картинку из кеша expo-image.
	 */
	imageCachePolicy?: ImageProps["cachePolicy"];
	aspectRatio?: number;
	isFavorite?: boolean;
	onPress?: () => void;
	onLongPress?: () => void;
	onFavoritePress?: () => void;
	onMenuPress?: () => void;
	favoriteLabel?: string;
	menuLabel?: string;
	testID?: string;
	style?: StyleProp<ViewStyle>;
}

function normalizeImageSource(
	source: MediaCardImageSource | undefined,
): ImageSource | null {
	if (source === undefined || source === null) {
		return null;
	}
	if (typeof source === "string") {
		const uri = source.trim();
		return uri === "" ? null : { uri };
	}
	if (source.uri === undefined || source.uri.trim() === "") {
		return null;
	}
	return source;
}

function CardAction({
	icon,
	label,
	onPress,
	testID,
	active = false,
	selected,
}: {
	icon: IoniconName;
	label: string;
	onPress: () => void;
	testID?: string;
	active?: boolean;
	selected?: boolean;
}) {
	const { colors, radii, spacing } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={label}
			accessibilityState={selected === undefined ? undefined : { selected }}
			onPress={onPress}
			testID={testID}
			hitSlop={8}
			style={({ pressed }) => [
				styles.actionButton,
				{
					backgroundColor: active ? colors.favorite : colors.overlay,
					borderRadius: radii.pill,
					marginLeft: spacing.xs,
				},
				pressed && styles.pressed,
			]}
		>
			<Ionicons name={icon} size={17} color={colors.onOverlay} />
		</Pressable>
	);
}

export function MediaCard({
	title,
	subtitle,
	duration,
	progress,
	badge,
	variant = "video",
	imageSource,
	imageCachePolicy,
	aspectRatio = 16 / 9,
	isFavorite = false,
	onPress,
	onLongPress,
	onFavoritePress,
	onMenuPress,
	favoriteLabel,
	menuLabel,
	testID,
	style,
}: MediaCardProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const image = normalizeImageSource(imageSource);
	const interactive = onPress !== undefined || onLongPress !== undefined;
	const showActions =
		onFavoritePress !== undefined || onMenuPress !== undefined;
	const favoriteText =
		favoriteLabel ?? (isFavorite ? t("media.unfavorite") : t("media.favorite"));
	const menuText = menuLabel ?? t("media.actions");
	// Содержимое одинаково для интерактивной и статичной карточки: у
	// неинтерактивной не должно быть disabled-состояния для скринридера.
	const cardContent = (
		<>
			<View
				style={[
					styles.cover,
					{
						aspectRatio,
						backgroundColor: colors.surfaceMuted,
						borderRadius: radii.sm,
					},
				]}
			>
				{image === null ? (
					<View style={styles.placeholder}>
						<Ionicons
							name={
								variant === "audio"
									? "musical-notes-outline"
									: "videocam-outline"
							}
							size={32}
							color={colors.textMuted}
						/>
					</View>
				) : (
					<Image
						source={image}
						style={StyleSheet.absoluteFill}
						contentFit="cover"
						cachePolicy={imageCachePolicy}
						transition={150}
						accessibilityIgnoresInvertColors
					/>
				)}
				{badge !== undefined && badge !== "" && (
					<View
						style={[
							styles.badge,
							{
								backgroundColor: colors.overlay,
								borderRadius: radii.sm,
								left: spacing.sm,
								top: spacing.sm,
								paddingHorizontal: spacing.sm,
							},
						]}
					>
						<Text
							style={[styles.overlayText, { color: colors.onOverlay }]}
							numberOfLines={1}
						>
							{badge}
						</Text>
					</View>
				)}
				{duration !== undefined && (
					<View
						style={[
							styles.duration,
							{
								backgroundColor: colors.overlay,
								borderRadius: radii.sm,
								bottom: spacing.sm,
								right: spacing.sm,
								paddingHorizontal: spacing.sm,
							},
						]}
					>
						<Text style={[styles.overlayText, { color: colors.onOverlay }]}>
							{formatDuration(duration)}
						</Text>
					</View>
				)}
				{progress !== undefined && (
					<View
						style={[styles.progressTrack, { backgroundColor: colors.overlay }]}
					>
						<View
							style={[
								styles.progressFill,
								{
									backgroundColor: colors.accent,
									width: `${clampProgress(progress) * 100}%`,
								},
							]}
						/>
					</View>
				)}
			</View>
			<View style={[styles.body, { padding: spacing.sm }]}>
				<Text style={[styles.title, { color: colors.text }]} numberOfLines={2}>
					{title}
				</Text>
				{subtitle !== undefined && subtitle !== "" && (
					<Text
						style={[styles.subtitle, { color: colors.textMuted }]}
						numberOfLines={1}
					>
						{subtitle}
					</Text>
				)}
			</View>
		</>
	);

	return (
		<View
			style={[
				styles.card,
				{
					backgroundColor: colors.surface,
					borderColor: colors.borderStrong,
					borderRadius: radii.md,
				},
				style,
			]}
		>
			{interactive ? (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={
						subtitle === undefined || subtitle === ""
							? title
							: `${title}, ${subtitle}`
					}
					onPress={onPress}
					onLongPress={onLongPress}
					testID={testID}
					style={({ pressed }) => [styles.content, pressed && styles.pressed]}
				>
					{cardContent}
				</Pressable>
			) : (
				<View style={styles.content} testID={testID}>
					{cardContent}
				</View>
			)}
			{showActions && (
				<View
					style={[styles.actions, { right: spacing.sm, top: spacing.sm }]}
					pointerEvents="box-none"
				>
					{onFavoritePress !== undefined && (
						<CardAction
							icon={isFavorite ? "heart" : "heart-outline"}
							label={favoriteText}
							onPress={onFavoritePress}
							testID={
								testID === undefined
									? undefined
									: `${testID}-favorite-${isFavorite ? "on" : "off"}`
							}
							active={isFavorite}
							selected={isFavorite}
						/>
					)}
					{onMenuPress !== undefined && (
						<CardAction
							icon="ellipsis-horizontal"
							label={menuText}
							onPress={onMenuPress}
							testID={testID === undefined ? undefined : `${testID}-menu`}
						/>
					)}
				</View>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	card: {
		borderWidth: 1,
		overflow: "hidden",
	},
	content: { width: "100%" },
	cover: {
		width: "100%",
		overflow: "hidden",
	},
	placeholder: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
	},
	badge: {
		position: "absolute",
		maxWidth: "60%",
		paddingVertical: 2,
	},
	duration: {
		position: "absolute",
		paddingVertical: 2,
	},
	progressTrack: {
		position: "absolute",
		left: 0,
		right: 0,
		bottom: 0,
		height: 4,
	},
	progressFill: { height: "100%" },
	overlayText: { fontSize: 11, fontWeight: "600" },
	body: { gap: 2 },
	title: { fontSize: 14, fontWeight: "600" },
	subtitle: { fontSize: 12 },
	actions: {
		position: "absolute",
		flexDirection: "row",
	},
	actionButton: {
		width: 30,
		height: 30,
		alignItems: "center",
		justifyContent: "center",
	},
	pressed: { opacity: 0.75 },
});

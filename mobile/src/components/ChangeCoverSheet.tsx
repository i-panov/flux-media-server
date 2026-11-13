import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { Image } from "expo-image";
import * as ImagePicker from "expo-image-picker";
import { useState } from "react";
import {
	ActivityIndicator,
	Modal,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import {
	coverErrorKey,
	coverUploadFile,
	isCoverTooLarge,
	useUploadCover,
} from "../api/cover";
import { t, useLanguage } from "../i18n";
import { type AuthSource, coverPath } from "../media/source";
import { useAuthImageSource } from "../media/useAuthImageSource";
import { useTheme } from "../theme/ThemeProvider";

interface ChangeCoverSheetProps {
	visible: boolean;
	media: Media;
	onClose: () => void;
	/** Вызывается после успешной загрузки: детали могут сбросить кэш постера. */
	onUploaded: () => void;
}

type CoverMessageKey = ReturnType<typeof coverErrorKey> | "cover.pickError";

function CoverPreview({
	source,
	hasCover,
}: {
	source: AuthSource | null;
	hasCover: boolean;
}) {
	const { colors, radii } = useTheme();
	return (
		<>
			<View
				style={[
					styles.preview,
					{
						backgroundColor: colors.surfaceMuted,
						borderRadius: radii.md,
					},
				]}
				accessible
				accessibilityLabel={t("cover.current")}
				testID="change-cover-preview"
			>
				{source === null ? (
					<Ionicons name="image-outline" size={36} color={colors.textMuted} />
				) : (
					<Image
						source={source}
						style={StyleSheet.absoluteFill}
						contentFit="cover"
						cachePolicy="none"
						transition={150}
						accessibilityIgnoresInvertColors
						testID="change-cover-image"
					/>
				)}
			</View>
			{!hasCover && (
				<Text style={[styles.hint, { color: colors.textMuted }]}>
					{t("cover.none")}
				</Text>
			)}
			<Text style={[styles.hint, { color: colors.textMuted }]}>
				{t("cover.hint")}
			</Text>
		</>
	);
}

function CoverStatus({
	uploaded,
	error,
}: {
	uploaded: boolean;
	error: CoverMessageKey | null;
}) {
	const { colors, spacing } = useTheme();
	if (!uploaded && error === null) {
		return null;
	}
	return (
		<>
			{uploaded && (
				<View
					style={[styles.notice, { gap: spacing.sm }]}
					accessibilityRole="alert"
					accessibilityLiveRegion="polite"
					testID="change-cover-uploaded"
				>
					<Ionicons
						name="checkmark-circle-outline"
						size={20}
						color={colors.accent}
					/>
					<Text style={[styles.noticeText, { color: colors.text }]}>
						{t("cover.uploaded")}
					</Text>
				</View>
			)}
			{error !== null && (
				<Text
					accessibilityRole="alert"
					accessibilityLiveRegion="polite"
					testID="change-cover-error"
					style={[styles.error, { color: colors.danger }]}
				>
					{t(error)}
				</Text>
			)}
		</>
	);
}

// Системный picker не автоматизируется в Maestro: поток проверяет только
// доступность кнопки в деталях, а выбор файла остаётся ручным сценарием.
export function ChangeCoverSheet({
	visible,
	media,
	onClose,
	onUploaded,
}: ChangeCoverSheetProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const insets = useSafeAreaInsets();
	const upload = useUploadCover(media.id);
	const [error, setError] = useState<CoverMessageKey | null>(null);
	const [uploaded, setUploaded] = useState(false);
	// URL обложки на сервере не меняется, а expo-image кэширует его по URI.
	// После загрузки добавляем версию, чтобы превью не осталось старым.
	const [version, setVersion] = useState(0);
	const hasCover = media.cover_url !== "" || version > 0;
	const previewPath = hasCover ? `${coverPath(media.id)}?v=${version}` : null;
	const preview = useAuthImageSource(previewPath);
	const busy = upload.isPending;
	// Закрыть можно и во время загрузки: сеть могла зависнуть, а
	// пользователь не должен оказаться заперт в модалке.
	const close = () => onClose();

	const choose = async (): Promise<void> => {
		if (busy) {
			return;
		}
		setError(null);
		setUploaded(false);
		try {
			// allowsEditing с aspect 1:1 — сервер не режет обложку сам, а
			// квадратная картинка не обрезается карточками в списках.
			const result = await ImagePicker.launchImageLibraryAsync({
				mediaTypes: ["images"],
				allowsEditing: true,
				aspect: [1, 1],
				quality: 0.9,
				exif: false,
			});
			if (result.canceled) {
				return;
			}
			const asset = result.assets[0];
			if (asset === undefined) {
				setError("cover.pickError");
				return;
			}
			if (isCoverTooLarge(asset.fileSize)) {
				setError("cover.tooLarge");
				return;
			}
			const file = coverUploadFile({
				uri: asset.uri,
				fileName: asset.fileName,
				mimeType: asset.mimeType,
			});
			if (file === null) {
				setError("cover.invalidType");
				return;
			}
			upload.mutate(file, {
				onSuccess: () => {
					setVersion(Date.now());
					setUploaded(true);
					onUploaded();
				},
				onError: (uploadError) => setError(coverErrorKey(uploadError)),
			});
		} catch {
			setError("cover.pickError");
		}
	};

	return (
		<Modal
			visible={visible}
			transparent
			animationType="slide"
			onRequestClose={close}
		>
			<View style={styles.overlay}>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.close")}
					accessibilityState={{ disabled: false }}
					onPress={close}
					testID="change-cover-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="change-cover-sheet"
					style={[
						styles.sheet,
						{
							backgroundColor: colors.surface,
							borderTopLeftRadius: radii.lg,
							borderTopRightRadius: radii.lg,
							gap: spacing.md,
							padding: spacing.lg,
							paddingBottom: spacing.lg + insets.bottom,
						},
					]}
				>
					<Text style={[styles.title, { color: colors.text }]}>
						{t("cover.title")}
					</Text>
					<CoverPreview source={preview} hasCover={hasCover} />
					<CoverStatus uploaded={uploaded} error={error} />
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("cover.choose")}
						accessibilityState={{ disabled: busy, busy }}
						disabled={busy}
						onPress={() => void choose()}
						testID="change-cover-choose"
						style={({ pressed }) => [
							styles.primary,
							{
								backgroundColor: colors.accent,
								borderRadius: radii.sm,
								paddingHorizontal: spacing.md,
								paddingVertical: spacing.md,
								gap: spacing.sm,
							},
							(pressed || busy) && styles.pressed,
						]}
					>
						{busy ? (
							<ActivityIndicator color={colors.onAccent} />
						) : (
							<Ionicons
								name="images-outline"
								size={20}
								color={colors.onAccent}
							/>
						)}
						<Text
							accessibilityLiveRegion="polite"
							style={[styles.primaryLabel, { color: colors.onAccent }]}
						>
							{busy ? t("cover.uploading") : t("cover.choose")}
						</Text>
					</Pressable>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={uploaded ? t("cover.done") : t("common.cancel")}
						accessibilityState={{ disabled: false }}
						onPress={close}
						testID="change-cover-close"
						style={({ pressed }) => [
							styles.secondary,
							{
								borderColor: colors.borderStrong,
								borderRadius: radii.sm,
								paddingVertical: spacing.sm,
							},
							(pressed || busy) && styles.pressed,
						]}
					>
						<Text style={[styles.secondaryLabel, { color: colors.text }]}>
							{uploaded ? t("cover.done") : t("common.cancel")}
						</Text>
					</Pressable>
				</View>
			</View>
		</Modal>
	);
}

const styles = StyleSheet.create({
	overlay: { flex: 1, justifyContent: "flex-end" },
	sheet: { width: "100%" },
	title: { fontSize: 20, fontWeight: "700" },
	preview: {
		width: 160,
		height: 160,
		alignSelf: "center",
		overflow: "hidden",
		alignItems: "center",
		justifyContent: "center",
	},
	hint: { fontSize: 13, lineHeight: 18 },
	notice: { flexDirection: "row", alignItems: "center" },
	noticeText: { flexShrink: 1, fontSize: 14, fontWeight: "600" },
	error: { fontSize: 14 },
	primary: {
		minHeight: 48,
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
	},
	primaryLabel: { fontSize: 16, fontWeight: "600" },
	secondary: {
		minHeight: 44,
		borderWidth: 1,
		alignItems: "center",
		justifyContent: "center",
	},
	secondaryLabel: { fontSize: 15, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

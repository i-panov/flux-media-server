import Ionicons from "@expo/vector-icons/Ionicons";
import type { ComponentProps } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { clampPercent } from "../api/upload";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import {
	formatUploadProgress,
	isActiveUploadStatus,
	type UploadItemStatus,
} from "../upload/queue";
import type { UploadQueueItem } from "../upload/useUploadQueue";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

function typeIcon(item: UploadQueueItem): IoniconName {
	switch (item.source.mediaType) {
		case "video":
			return "videocam-outline";
		case "audio":
			return "musical-notes-outline";
		default:
			return "image-outline";
	}
}

function typeLabel(item: UploadQueueItem): string {
	switch (item.source.mediaType) {
		case "video":
			return t("upload.typeVideo");
		case "audio":
			return t("upload.typeAudio");
		default:
			return t("upload.typeImage");
	}
}

function statusLabel(status: UploadItemStatus): string {
	switch (status) {
		case "queued":
			return t("upload.statusQueued");
		case "uploading":
			return t("upload.statusUploading");
		case "processing":
			return t("upload.statusProcessing");
		case "done":
			return t("upload.statusDone");
		case "cancelled":
			return t("upload.statusCancelled");
		default:
			return t("upload.statusError");
	}
}

function statusColor(status: UploadItemStatus, danger: string, muted: string) {
	if (status === "error") {
		return danger;
	}
	if (status === "done") {
		return;
	}
	return muted;
}

interface UploadQueueRowProps {
	readonly item: UploadQueueItem;
	readonly onCancel: () => void;
	readonly onRetry: () => void;
	readonly onForceRetry: () => void;
}

export function UploadQueueRow({
	item,
	onCancel,
	onRetry,
	onForceRetry,
}: UploadQueueRowProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const active = isActiveUploadStatus(item.status);
	const percent = item.progress === null ? null : clampPercent(item.progress);
	const duplicateText =
		item.duplicate === null
			? item.error || t("upload.duplicateUnknown")
			: t("upload.duplicate", { title: item.duplicate.title });

	return (
		<View
			testID={`upload-item-${item.key}`}
			style={[
				styles.row,
				{
					borderColor: colors.border,
					backgroundColor: colors.surface,
					borderRadius: radii.md,
					padding: spacing.md,
					gap: spacing.sm,
				},
			]}
		>
			<View style={styles.header}>
				<Ionicons
					name={typeIcon(item)}
					size={20}
					color={colors.textMuted}
					accessibilityElementsHidden
					importantForAccessibility="no"
				/>
				<Text numberOfLines={1} style={[styles.name, { color: colors.text }]}>
					{item.source.name}
				</Text>
			</View>

			<View style={styles.meta}>
				<Text
					testID={`upload-status-${item.key}`}
					accessibilityLiveRegion="polite"
					style={[
						styles.status,
						{
							color: statusColor(item.status, colors.danger, colors.textMuted),
						},
						item.status === "done" && { color: colors.accent },
					]}
				>
					{statusLabel(item.status)}
				</Text>
				<Text style={[styles.type, { color: colors.textMuted }]}>
					{typeLabel(item)}
				</Text>
				{percent !== null && (
					<Text style={[styles.percent, { color: colors.textMuted }]}>
						{formatUploadProgress(percent)}
					</Text>
				)}
			</View>

			{active && percent !== null && (
				<View
					testID={`upload-progress-${item.key}`}
					accessibilityRole="progressbar"
					accessibilityLabel={t("upload.progressLabel")}
					accessibilityValue={{ min: 0, max: 100, now: percent }}
					style={[styles.track, { backgroundColor: colors.surfaceMuted }]}
				>
					<View
						style={[
							styles.fill,
							{
								backgroundColor: colors.accent,
								width: `${percent}%`,
							},
						]}
					/>
				</View>
			)}

			{active && percent === null && (
				<ActivityIndicator color={colors.accent} />
			)}

			{item.status === "done" && (
				<Text
					testID={`upload-done-${item.key}`}
					style={[styles.message, { color: colors.textMuted }]}
				>
					{item.mediaTitle}
				</Text>
			)}

			{item.status === "error" && item.duplicate !== null && (
				<Text style={[styles.message, { color: colors.danger }]}>
					{duplicateText}
				</Text>
			)}

			{item.status === "error" && item.duplicate === null && (
				<Text style={[styles.message, { color: colors.danger }]}>
					{item.error || t("upload.errorFallback")}
				</Text>
			)}

			<View style={[styles.actions, { gap: spacing.sm }]}>
				{active && (
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={`${t("upload.cancel")}: ${item.source.name}`}
						onPress={onCancel}
						testID={`upload-cancel-${item.key}`}
						style={({ pressed }) => [
							styles.button,
							{ borderColor: colors.controlBorder, borderRadius: radii.sm },
							pressed && styles.pressed,
						]}
					>
						<Text style={{ color: colors.text }}>{t("upload.cancel")}</Text>
					</Pressable>
				)}
				{(item.status === "error" || item.status === "cancelled") && (
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={`${t("upload.retry")}: ${item.source.name}`}
						onPress={onRetry}
						testID={`upload-retry-${item.key}`}
						style={({ pressed }) => [
							styles.button,
							{ borderColor: colors.accent, borderRadius: radii.sm },
							pressed && styles.pressed,
						]}
					>
						<Text style={{ color: colors.accent }}>{t("upload.retry")}</Text>
					</Pressable>
				)}
				{item.status === "error" && item.duplicate !== null && (
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={`${t("upload.forceRetry")}: ${item.source.name}`}
						onPress={onForceRetry}
						testID={`upload-force-${item.key}`}
						style={({ pressed }) => [
							styles.button,
							{
								borderColor: colors.accent,
								backgroundColor: colors.accent,
								borderRadius: radii.sm,
							},
							pressed && styles.pressed,
						]}
					>
						<Text style={{ color: colors.onAccent }}>
							{t("upload.forceRetry")}
						</Text>
					</Pressable>
				)}
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	row: { borderWidth: 1 },
	header: { flexDirection: "row", alignItems: "center", gap: 8 },
	name: { flex: 1, fontSize: 15, fontWeight: "600" },
	meta: { flexDirection: "row", alignItems: "center", gap: 8 },
	status: { fontSize: 13, fontWeight: "600" },
	type: { fontSize: 12 },
	percent: { fontSize: 12, marginLeft: "auto" },
	track: { height: 6, borderRadius: 3, overflow: "hidden" },
	fill: { height: "100%" },
	message: { fontSize: 13, lineHeight: 18 },
	actions: { flexDirection: "row", flexWrap: "wrap" },
	button: {
		minHeight: 44,
		paddingHorizontal: 12,
		alignItems: "center",
		justifyContent: "center",
		borderWidth: 1,
	},
	pressed: { opacity: 0.7 },
});

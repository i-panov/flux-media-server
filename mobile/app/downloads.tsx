import Ionicons from "@expo/vector-icons/Ionicons";
import type { MediaType } from "@flux/shared";
import { router } from "expo-router";
import {
	ActivityIndicator,
	Alert,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { formatFileSize } from "../src/api/upload";
import { AuthGate } from "../src/components/AuthGate";
import { EmptyState } from "../src/components/EmptyState";
import { Screen } from "../src/components/Screen";
import {
	type ActiveDownload,
	useDownloadActions,
	useDownloadState,
} from "../src/downloads/DownloadProvider";
import type {
	DownloadEntry,
	DownloadFailure,
} from "../src/downloads/downloadStore";
import { t, useLanguage } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";

function closeDownloads(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/library");
}

function downloadFailureLabel(failure: DownloadFailure | null): string {
	switch (failure) {
		case "status":
			return t("downloads.errorStatus");
		case "size":
			return t("downloads.errorSize");
		case "storage":
			return t("downloads.errorStorage");
		case "timeout":
			return t("downloads.errorTimeout");
		case "network":
			return t("downloads.errorNetwork");
		default:
			return t("downloads.errorUnknown");
	}
}

function mediaTypeLabel(type: MediaType): string {
	switch (type) {
		case "audio":
			return t("downloads.typeAudio");
		case "image":
			return t("downloads.typeImage");
		default:
			return t("downloads.typeVideo");
	}
}

function DownloadsHeader() {
	const { colors, spacing } = useTheme();
	return (
		<View style={[styles.header, { gap: spacing.sm }]}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("downloads.back")}
				onPress={closeDownloads}
				testID="downloads-back"
				hitSlop={8}
				style={({ pressed }) => [
					styles.headerButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<Text style={[styles.title, { color: colors.text }]}>
				{t("downloads.title")}
			</Text>
			<View style={styles.headerButton} />
		</View>
	);
}

function DownloadProgress({
	progress,
	testID,
}: {
	progress: number | null;
	testID: string;
}) {
	const { colors } = useTheme();
	if (progress === null) {
		return (
			<ActivityIndicator
				accessibilityRole="progressbar"
				accessibilityLabel={t("downloads.progressLabel")}
				testID={testID}
				color={colors.accent}
				style={styles.progressSpinner}
			/>
		);
	}
	return (
		<View
			accessibilityRole="progressbar"
			accessibilityLabel={t("downloads.progressLabel")}
			accessibilityValue={{ min: 0, max: 100, now: Math.round(progress * 100) }}
			testID={testID}
			style={[styles.progressTrack, { backgroundColor: colors.surfaceMuted }]}
		>
			<View
				style={[
					styles.progressFill,
					{
						backgroundColor: colors.accent,
						width: `${Math.round(progress * 100)}%`,
					},
				]}
			/>
		</View>
	);
}

function ActiveRow({ item }: { item: ActiveDownload }) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const { cancel, retry } = useDownloadActions();
	const failed = item.status === "error";
	const percent =
		item.progress === null ? null : Math.round(item.progress * 100);
	const statusText = failed
		? downloadFailureLabel(item.failure)
		: percent === null
			? t("downloads.downloading")
			: `${t("downloads.downloading")} · ${percent}%`;

	return (
		<View
			testID={`download-active-${item.media.id}`}
			style={[
				styles.row,
				{
					backgroundColor: colors.surface,
					borderColor: failed ? colors.danger : colors.border,
					borderRadius: radii.md,
					padding: spacing.md,
					gap: spacing.sm,
				},
			]}
		>
			<View style={styles.rowText}>
				<Text
					numberOfLines={2}
					style={[styles.rowTitle, { color: colors.text }]}
				>
					{item.media.title}
				</Text>
				<Text
					accessibilityLiveRegion="polite"
					numberOfLines={2}
					style={[
						styles.rowMeta,
						{ color: failed ? colors.danger : colors.textMuted },
					]}
				>
					{statusText}
				</Text>
			</View>
			<View style={[styles.rowActions, { gap: spacing.xs }]}>
				{failed ? (
					<>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("downloads.retry")}
							onPress={() => retry(item.media)}
							testID={`download-active-retry-${item.media.id}`}
							hitSlop={8}
							style={({ pressed }) => [
								styles.actionButton,
								pressed && styles.pressed,
							]}
						>
							<Ionicons name="refresh" size={20} color={colors.accent} />
						</Pressable>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("downloads.dismiss")}
							onPress={() => cancel(item.media.id)}
							testID={`download-active-dismiss-${item.media.id}`}
							hitSlop={8}
							style={({ pressed }) => [
								styles.actionButton,
								pressed && styles.pressed,
							]}
						>
							<Ionicons name="close" size={20} color={colors.textMuted} />
						</Pressable>
					</>
				) : (
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("downloads.cancel")}
						onPress={() => cancel(item.media.id)}
						testID={`download-active-cancel-${item.media.id}`}
						hitSlop={8}
						style={({ pressed }) => [
							styles.actionButton,
							pressed && styles.pressed,
						]}
					>
						<Ionicons name="close" size={20} color={colors.textMuted} />
					</Pressable>
				)}
			</View>
			{!failed && (
				<DownloadProgress
					progress={item.progress}
					testID={`download-active-progress-${item.media.id}`}
				/>
			)}
		</View>
	);
}

function EntryRow({ entry }: { entry: DownloadEntry }) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const { remove } = useDownloadActions();

	const confirmDelete = () => {
		Alert.alert(t("downloads.deleteTitle"), t("downloads.deleteConfirm"), [
			{ text: t("common.cancel"), style: "cancel" },
			{
				text: t("downloads.delete"),
				style: "destructive",
				onPress: () => remove(entry.mediaId),
			},
		]);
	};

	return (
		<View
			testID={`download-item-${entry.mediaId}`}
			style={[
				styles.row,
				{
					backgroundColor: colors.surface,
					borderColor: colors.border,
					borderRadius: radii.md,
					padding: spacing.md,
					gap: spacing.sm,
				},
			]}
		>
			<Ionicons
				name={entry.type === "audio" ? "musical-notes-outline" : "film-outline"}
				size={22}
				color={colors.accent}
			/>
			<View style={styles.rowText}>
				<Text
					numberOfLines={2}
					style={[styles.rowTitle, { color: colors.text }]}
				>
					{entry.title}
				</Text>
				<Text style={[styles.rowMeta, { color: colors.textMuted }]}>
					{mediaTypeLabel(entry.type)} · {formatFileSize(entry.size)}
				</Text>
			</View>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("downloads.delete")}
				onPress={confirmDelete}
				testID={`download-delete-${entry.mediaId}`}
				hitSlop={8}
				style={({ pressed }) => [
					styles.actionButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="trash-outline" size={20} color={colors.danger} />
			</Pressable>
		</View>
	);
}

function DownloadsContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const { entries, active } = useDownloadState();
	const totalBytes = entries.reduce((sum, entry) => sum + entry.size, 0);
	const empty = entries.length === 0 && active.length === 0;

	return (
		<Screen scroll testID="downloads-screen">
			<DownloadsHeader />
			<Text style={[styles.hint, { color: colors.textMuted }]}>
				{t("downloads.subtitle")}
			</Text>
			{!empty && (
				<Text
					testID="downloads-summary"
					style={[styles.summary, { color: colors.textMuted }]}
				>
					{t("downloads.summary", {
						count: entries.length,
						size: formatFileSize(totalBytes),
					})}
				</Text>
			)}
			{active.length > 0 && (
				<View style={{ gap: spacing.xs }} testID="downloads-active">
					<Text style={[styles.sectionTitle, { color: colors.text }]}>
						{t("downloads.activeTitle")}
					</Text>
					{active.map((item) => (
						<ActiveRow key={item.media.id} item={item} />
					))}
				</View>
			)}
			{entries.length > 0 && (
				<View style={{ gap: spacing.xs }} testID="downloads-list">
					<Text style={[styles.sectionTitle, { color: colors.text }]}>
						{t("downloads.doneTitle")}
					</Text>
					{entries.map((entry) => (
						<EntryRow key={entry.mediaId} entry={entry} />
					))}
				</View>
			)}
			{empty && (
				<EmptyState
					icon="cloud-download-outline"
					title={t("downloads.empty")}
					description={t("downloads.emptyHint")}
					testID="downloads-empty"
				/>
			)}
		</Screen>
	);
}

export default function DownloadsScreen() {
	return (
		<AuthGate>
			<DownloadsContent />
		</AuthGate>
	);
}

const styles = StyleSheet.create({
	header: { flexDirection: "row", alignItems: "center" },
	headerButton: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	title: { flex: 1, fontSize: 22, fontWeight: "700" },
	hint: { fontSize: 14, lineHeight: 20 },
	summary: { fontSize: 13, fontWeight: "600" },
	sectionTitle: { fontSize: 17, fontWeight: "700" },
	row: {
		flexDirection: "row",
		alignItems: "center",
		flexWrap: "wrap",
		borderWidth: 1,
	},
	rowText: { flex: 1, gap: 2 },
	rowTitle: { fontSize: 16, fontWeight: "600" },
	rowMeta: { fontSize: 13 },
	rowActions: { flexDirection: "row", alignItems: "center" },
	actionButton: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	progressTrack: {
		width: "100%",
		height: 4,
		borderRadius: 2,
		overflow: "hidden",
	},
	progressFill: { height: "100%" },
	progressSpinner: { width: "100%", height: 4 },
	pressed: { opacity: 0.7 },
});

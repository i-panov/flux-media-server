import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import {
	ActivityIndicator,
	Alert,
	BackHandler,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { formatFileSize, MAX_UPLOAD_BYTES } from "../src/api/upload";
import { useSession } from "../src/auth/session";
import { AuthGate } from "../src/components/AuthGate";
import { EmptyState } from "../src/components/EmptyState";
import { Screen } from "../src/components/Screen";
import { UploadQueueRow } from "../src/components/UploadQueueRow";
import { t, useLanguage } from "../src/i18n";
import { useTheme } from "../src/theme/ThemeProvider";
import { pickUploadSources } from "../src/upload/picker";
import { useUploadQueue } from "../src/upload/useUploadQueue";

function closeUpload(): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace("/library");
}

function UploadHeader({ onBack }: { onBack: () => void }) {
	const { colors, spacing } = useTheme();
	return (
		<View style={[styles.header, { gap: spacing.sm }]}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("upload.back")}
				onPress={onBack}
				testID="upload-back"
				hitSlop={8}
				style={({ pressed }) => [
					styles.headerButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<Text style={[styles.title, { color: colors.text }]}>
				{t("upload.title")}
			</Text>
			<View style={styles.headerButton} />
		</View>
	);
}

function AdminOnlyNotice() {
	const { colors, radii, spacing } = useTheme();
	return (
		<>
			<UploadHeader onBack={closeUpload} />
			<View
				testID="upload-admin-only"
				accessibilityRole="alert"
				style={[
					styles.noticeCard,
					{
						borderColor: colors.danger,
						backgroundColor: colors.surface,
						borderRadius: radii.md,
						padding: spacing.md,
					},
				]}
			>
				<Ionicons name="lock-closed-outline" size={20} color={colors.danger} />
				<Text style={[styles.noticeText, { color: colors.text }]}>
					{t("upload.adminOnly")}
				</Text>
			</View>
		</>
	);
}

function UploadContent() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const session = useSession();
	const queue = useUploadQueue();
	const [picking, setPicking] = useState(false);
	const [pickerError, setPickerError] = useState<string | null>(null);

	// Предупреждаем при back в шапке и Android hardware back. iOS
	// свайп-назад системный и не перехватывается, но уход оттуда отменит
	// очередь так же, как обычный unmount.
	const confirmLeave = useCallback((): void => {
		if (!queue.busy) {
			closeUpload();
			return;
		}
		Alert.alert(t("upload.activeTitle"), t("upload.activeConfirm"), [
			{ text: t("common.cancel"), style: "cancel" },
			{ text: t("upload.leave"), style: "destructive", onPress: closeUpload },
		]);
	}, [queue.busy]);

	useEffect(() => {
		if (!queue.busy) {
			return;
		}
		const subscription = BackHandler.addEventListener(
			"hardwareBackPress",
			() => {
				confirmLeave();
				return true;
			},
		);
		return () => subscription.remove();
	}, [confirmLeave, queue.busy]);

	if (session.data?.is_admin !== true) {
		return (
			<Screen testID="upload-screen">
				<AdminOnlyNotice />
			</Screen>
		);
	}

	const chooseFiles = async (): Promise<void> => {
		if (picking) {
			return;
		}
		setPicking(true);
		setPickerError(null);
		try {
			const picked = await pickUploadSources();
			const oversized = picked.oversized[0];
			if (oversized !== undefined) {
				setPickerError(
					t("upload.fileTooLarge", {
						name: oversized.name,
						limit: formatFileSize(MAX_UPLOAD_BYTES),
					}),
				);
			} else if (picked.skipped > 0) {
				setPickerError(t("upload.skipped", { count: picked.skipped }));
			}
			if (picked.sources.length > 0) {
				queue.addFiles(picked.sources);
			}
		} catch {
			setPickerError(t("upload.pickError"));
		} finally {
			setPicking(false);
		}
	};

	return (
		<Screen scroll testID="upload-screen">
			<UploadHeader onBack={confirmLeave} />
			<Text style={[styles.hint, { color: colors.textMuted }]}>
				{t("upload.subtitle")}
			</Text>

			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("upload.add")}
				accessibilityState={{ disabled: picking }}
				disabled={picking}
				onPress={() => void chooseFiles()}
				testID="upload-add"
				style={({ pressed }) => [
					styles.addButton,
					{
						backgroundColor: colors.accent,
						borderRadius: radii.md,
						paddingHorizontal: spacing.lg,
						gap: spacing.sm,
					},
					(pressed || picking) && styles.pressed,
				]}
			>
				{picking ? (
					<ActivityIndicator color={colors.onAccent} />
				) : (
					<Ionicons
						name="cloud-upload-outline"
						size={20}
						color={colors.onAccent}
					/>
				)}
				<Text style={[styles.addLabel, { color: colors.onAccent }]}>
					{t("upload.add")}
				</Text>
			</Pressable>

			{pickerError !== null && (
				<Text
					testID="upload-picker-error"
					accessibilityRole="alert"
					style={[styles.error, { color: colors.danger }]}
				>
					{pickerError}
				</Text>
			)}

			{/* Системных уведомлений нет: баннер живёт только на этом экране. */}
			{queue.lastCompleted !== null && (
				<View
					testID="upload-notice"
					accessibilityRole="alert"
					accessibilityLiveRegion="polite"
					style={[
						styles.noticeCard,
						{
							borderColor: colors.accent,
							backgroundColor: colors.surface,
							borderRadius: radii.md,
							padding: spacing.md,
						},
					]}
				>
					<Ionicons
						name="checkmark-circle-outline"
						size={20}
						color={colors.accent}
					/>
					<View style={styles.noticeBody}>
						<Text style={[styles.noticeText, { color: colors.text }]}>
							{t("upload.noticeDone", {
								title: queue.lastCompleted.title,
							})}
						</Text>
						<Text style={[styles.noticeHint, { color: colors.textMuted }]}>
							{t("upload.noticeHint")}
						</Text>
					</View>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("upload.dismiss")}
						onPress={queue.dismissCompleted}
						testID="upload-notice-dismiss"
						hitSlop={8}
						style={({ pressed }) => [styles.dismiss, pressed && styles.pressed]}
					>
						<Ionicons name="close" size={20} color={colors.textMuted} />
					</Pressable>
				</View>
			)}

			{queue.items.length === 0 ? (
				<EmptyState
					icon="cloud-upload-outline"
					title={t("upload.empty")}
					description={t("upload.emptyHint")}
					testID="upload-empty"
				/>
			) : (
				<View style={[styles.list, { gap: spacing.sm }]} testID="upload-list">
					{queue.items.map((item) => (
						<UploadQueueRow
							key={item.key}
							item={item}
							onCancel={() => queue.cancelItem(item.key)}
							onRetry={() => queue.retryItem(item.key)}
							onForceRetry={() => queue.forceRetryItem(item.key)}
						/>
					))}
				</View>
			)}
		</Screen>
	);
}

export default function UploadScreen() {
	return (
		<AuthGate>
			<UploadContent />
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
	hint: { fontSize: 14 },
	addButton: {
		minHeight: 48,
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
	},
	addLabel: { fontSize: 16, fontWeight: "600" },
	error: { fontSize: 14 },
	noticeCard: {
		flexDirection: "row",
		alignItems: "flex-start",
		gap: 8,
		borderWidth: 1,
	},
	noticeBody: { flex: 1, gap: 4 },
	noticeText: { fontSize: 14, fontWeight: "600" },
	noticeHint: { fontSize: 12, lineHeight: 16 },
	dismiss: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	list: { flexDirection: "column" },
	pressed: { opacity: 0.7 },
});

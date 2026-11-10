import type { Collection } from "@flux/shared";
import {
	ActivityIndicator,
	Modal,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useCollectionStats, useDeleteCollection } from "../api/collections";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface DeleteCollectionModalProps {
	visible: boolean;
	collection: Collection;
	onClose: () => void;
	onDeleted: () => void;
}

export function DeleteCollectionModal({
	visible,
	collection,
	onClose,
	onDeleted,
}: DeleteCollectionModalProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const stats = useCollectionStats(collection.id, visible);
	const remove = useDeleteCollection();

	const statsText =
		stats.data === undefined
			? null
			: t("collections.deleteStats", {
					items: stats.data.items,
					subcollections: stats.data.subcollections,
				});

	return (
		<Modal
			visible={visible}
			transparent
			animationType="fade"
			onRequestClose={onClose}
		>
			<View style={styles.overlay}>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.close")}
					onPress={onClose}
					testID="delete-collection-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="delete-collection-modal"
					style={[
						styles.card,
						{
							backgroundColor: colors.surface,
							borderColor: colors.border,
							borderRadius: radii.lg,
							gap: spacing.md,
							padding: spacing.lg,
						},
					]}
				>
					<Text style={[styles.title, { color: colors.text }]}>
						{t("collections.deleteTitle")}
					</Text>
					<Text style={[styles.body, { color: colors.text }]}>
						{t("collections.deleteConfirm")}
					</Text>
					{stats.isPending ? (
						<ActivityIndicator size="small" color={colors.accent} />
					) : stats.isError ? (
						<View style={[styles.statsError, { gap: spacing.sm }]}>
							<Text
								accessibilityRole="alert"
								style={[styles.error, { color: colors.danger }]}
							>
								{t("collections.statsError")}
							</Text>
							<Pressable
								accessibilityRole="button"
								accessibilityLabel={t("common.retry")}
								onPress={() => void stats.refetch()}
								testID="delete-collection-stats-retry"
								style={({ pressed }) => [
									styles.statsRetry,
									pressed && styles.pressed,
								]}
							>
								<Text style={{ color: colors.accent, fontWeight: "600" }}>
									{t("common.retry")}
								</Text>
							</Pressable>
						</View>
					) : (
						statsText !== null && (
							<Text
								testID="delete-collection-stats"
								style={[styles.stats, { color: colors.textMuted }]}
							>
								{statsText}
							</Text>
						)
					)}
					{remove.isError && (
						<Text
							accessibilityRole="alert"
							style={[styles.error, { color: colors.danger }]}
						>
							{t("collections.deleteError")}
						</Text>
					)}
					<View style={[styles.actions, { gap: spacing.sm }]}>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.cancel")}
							onPress={onClose}
							testID="delete-collection-cancel"
							style={({ pressed }) => [
								styles.button,
								{
									borderColor: colors.borderStrong,
									borderRadius: radii.sm,
									paddingHorizontal: spacing.md,
								},
								pressed && styles.pressed,
							]}
						>
							<Text style={[styles.buttonLabel, { color: colors.text }]}>
								{t("common.cancel")}
							</Text>
						</Pressable>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("collections.delete")}
							accessibilityState={{ disabled: remove.isPending }}
							disabled={remove.isPending}
							onPress={() => {
								remove.mutate(collection.id, {
									onSuccess: () => {
										onClose();
										onDeleted();
									},
								});
							}}
							testID="delete-collection-confirm"
							style={({ pressed }) => [
								styles.button,
								{
									backgroundColor: colors.danger,
									borderColor: colors.danger,
									borderRadius: radii.sm,
									paddingHorizontal: spacing.md,
								},
								pressed && styles.pressed,
							]}
						>
							{remove.isPending ? (
								<ActivityIndicator size="small" color={colors.onAccent} />
							) : (
								<Text style={[styles.buttonLabel, { color: colors.onAccent }]}>
									{t("collections.delete")}
								</Text>
							)}
						</Pressable>
					</View>
				</View>
			</View>
		</Modal>
	);
}

const styles = StyleSheet.create({
	overlay: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
		padding: 24,
	},
	card: { width: "100%", maxWidth: 420, borderWidth: 1 },
	title: { fontSize: 18, fontWeight: "700" },
	body: { fontSize: 14, lineHeight: 20 },
	stats: { fontSize: 13, lineHeight: 18 },
	statsError: { flexDirection: "row", alignItems: "center" },
	statsRetry: {
		minHeight: 44,
		justifyContent: "center",
		paddingHorizontal: 8,
	},
	error: { flex: 1, fontSize: 13, lineHeight: 18 },
	actions: { flexDirection: "row", justifyContent: "flex-end" },
	button: {
		minHeight: 44,
		minWidth: 88,
		alignItems: "center",
		justifyContent: "center",
		borderWidth: 1,
	},
	buttonLabel: { fontSize: 15, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

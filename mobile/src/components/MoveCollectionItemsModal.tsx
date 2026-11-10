import type { BulkResult, Collection } from "@flux/shared";
import {
	ActivityIndicator,
	Modal,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useBulkMoveCollectionItems } from "../api/collections";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { CollectionPickList } from "./CollectionPickList";

interface MoveCollectionItemsModalProps {
	visible: boolean;
	collection: Collection;
	collections: readonly Collection[];
	mediaIds: readonly number[];
	onClose: () => void;
	onMoved: (result: BulkResult) => void;
}

// Перенос одного или нескольких элементов в другую коллекцию того же
// типа. Исходная коллекция исключена; сервер дополнительно проверяет тип
// и дубликаты, а частичный успех возвращает в BulkResult.
export function MoveCollectionItemsModal({
	visible,
	collection,
	collections,
	mediaIds,
	onClose,
	onMoved,
}: MoveCollectionItemsModalProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const move = useBulkMoveCollectionItems();
	const title =
		mediaIds.length > 1
			? t("collections.bulkMoveTitle")
			: t("collections.moveTitle");

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
					testID="move-items-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="move-items-modal"
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
					<Text style={[styles.title, { color: colors.text }]}>{title}</Text>
					<CollectionPickList
						collections={collections}
						type={collection.type}
						excludeIds={new Set([collection.id])}
						allowRoot={false}
						pending={move.isPending}
						onPick={(toCollectionId) => {
							if (toCollectionId === null) {
								return;
							}
							move.mutate(
								{
									sourceId: collection.id,
									mediaIds: [...mediaIds],
									toCollectionId,
								},
								{ onSuccess: onMoved },
							);
						}}
					/>
					<View style={styles.actions}>
						{move.isError && (
							<Text
								accessibilityRole="alert"
								style={[styles.error, { color: colors.danger }]}
							>
								{t("collections.moveError")}
							</Text>
						)}
						{move.isPending && (
							<ActivityIndicator size="small" color={colors.accent} />
						)}
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.cancel")}
							onPress={onClose}
							testID="move-items-cancel"
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
	error: { flex: 1, fontSize: 13, lineHeight: 18 },
	actions: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "flex-end",
		gap: 8,
	},
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

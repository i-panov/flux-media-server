import type { Collection } from "@flux/shared";
import {
	ActivityIndicator,
	Modal,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useMoveCollection } from "../api/collections";
import { collectionDescendantIds } from "../collections/tree";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { CollectionPickList } from "./CollectionPickList";

interface MoveCollectionModalProps {
	visible: boolean;
	collection: Collection;
	collections: readonly Collection[];
	onClose: () => void;
}

// Переезд коллекции под другого родителя или в корень. Себя и потомков
// исключаем из целей: сервер тоже проверяет цикл, но молчащая кнопка
// понятнее ошибки после нажатия.
export function MoveCollectionModal({
	visible,
	collection,
	collections,
	onClose,
}: MoveCollectionModalProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const move = useMoveCollection();
	const excluded = collectionDescendantIds(collections, collection.id);

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
					testID="collection-move-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="collection-move-modal"
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
						{t("collections.moveCollectionTitle")}
					</Text>
					<CollectionPickList
						collections={collections}
						type={collection.type}
						excludeIds={excluded}
						allowRoot
						pending={move.isPending}
						onPick={(parentId) => {
							move.mutate(
								{ id: collection.id, parentId },
								{ onSuccess: onClose },
							);
						}}
					/>
					<View style={styles.actions}>
						{move.isError && (
							<Text
								accessibilityRole="alert"
								style={[styles.error, { color: colors.danger }]}
							>
								{t("collections.moveCollectionError")}
							</Text>
						)}
						{move.isPending && (
							<ActivityIndicator size="small" color={colors.accent} />
						)}
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.cancel")}
							onPress={onClose}
							testID="collection-move-cancel"
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

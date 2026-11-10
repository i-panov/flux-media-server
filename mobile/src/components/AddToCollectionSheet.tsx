import Ionicons from "@expo/vector-icons/Ionicons";
import type { Collection } from "@flux/shared";
import { useState } from "react";
import {
	ActivityIndicator,
	Alert,
	Modal,
	Pressable,
	ScrollView,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import {
	type AddableCollectionType,
	isAlreadyInCollection,
	useAddMediaToCollection,
	useCollectionsByType,
} from "../api/collections";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { CreateCollectionModal } from "./CreateCollectionModal";

interface AddToCollectionSheetProps {
	visible: boolean;
	mediaId: number;
	/** Тип коллекции совпадает с типом медиа: видео или аудио. */
	type: AddableCollectionType;
	onClose: () => void;
}

// Bottom sheet выбора коллекции нужного типа. Новую коллекцию можно
// создать прямо здесь: после создания медиа сразу добавляется в неё, без
// второго похода в детали.
export function AddToCollectionSheet({
	visible,
	mediaId,
	type,
	onClose,
}: AddToCollectionSheetProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const insets = useSafeAreaInsets();
	const collections = useCollectionsByType(type);
	const add = useAddMediaToCollection();
	const [createOpen, setCreateOpen] = useState(false);
	const items = collections.data ?? [];

	const choose = (collectionId: number) => {
		add.mutate(
			{ collectionId, mediaId },
			{
				onSuccess: onClose,
				onError: (error) => {
					Alert.alert(
						t("collections.addTitle"),
						isAlreadyInCollection(error)
							? t("collections.duplicate")
							: t("collections.addError"),
					);
				},
			},
		);
	};

	const addToCreated = (collection: Collection) => {
		setCreateOpen(false);
		choose(collection.id);
	};

	return (
		<Modal
			visible={visible}
			transparent
			animationType="slide"
			onRequestClose={onClose}
		>
			<View style={styles.overlay}>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.close")}
					onPress={onClose}
					testID="add-to-collection-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="add-to-collection-sheet"
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
						{t("collections.addTitle")}
					</Text>

					{collections.isPending ? (
						<ActivityIndicator color={colors.accent} />
					) : collections.isError ? (
						<View style={[styles.message, { gap: spacing.sm }]}>
							<Text style={{ color: colors.danger }}>
								{t("collections.loadError")}
							</Text>
							<Pressable
								accessibilityRole="button"
								accessibilityLabel={t("common.retry")}
								onPress={() => void collections.refetch()}
								testID="add-to-collection-retry"
								style={styles.retry}
							>
								<Text style={{ color: colors.accent, fontWeight: "600" }}>
									{t("common.retry")}
								</Text>
							</Pressable>
						</View>
					) : items.length === 0 ? (
						<Text style={{ color: colors.textMuted }}>
							{t("collections.emptyForType")}
						</Text>
					) : (
						<ScrollView
							style={styles.list}
							contentContainerStyle={{ gap: spacing.xs }}
						>
							{items.map((collection) => (
								<Pressable
									key={collection.id}
									accessibilityRole="button"
									accessibilityLabel={collection.name}
									disabled={add.isPending}
									onPress={() => choose(collection.id)}
									testID={`add-to-collection-${collection.id}`}
									style={({ pressed }) => [
										styles.collectionRow,
										{
											backgroundColor: colors.surfaceMuted,
											borderRadius: radii.sm,
											paddingHorizontal: spacing.md,
											paddingVertical: spacing.md,
										},
										(pressed || add.isPending) && styles.pressed,
									]}
								>
									<Ionicons
										name="folder-open-outline"
										size={18}
										color={colors.text}
									/>
									<Text style={[styles.collectionName, { color: colors.text }]}>
										{collection.name}
									</Text>
								</Pressable>
							))}
						</ScrollView>
					)}

					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("collections.create")}
						onPress={() => setCreateOpen(true)}
						testID="add-to-collection-create"
						style={({ pressed }) => [
							styles.create,
							{
								borderColor: colors.accent,
								borderRadius: radii.sm,
								paddingVertical: spacing.sm,
							},
							pressed && styles.pressed,
						]}
					>
						<Ionicons name="add" size={18} color={colors.accent} />
						<Text style={[styles.cancelLabel, { color: colors.accent }]}>
							{t("collections.create")}
						</Text>
					</Pressable>
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={t("common.cancel")}
						onPress={onClose}
						testID="add-to-collection-cancel"
						style={({ pressed }) => [
							styles.cancel,
							{
								borderColor: colors.borderStrong,
								borderRadius: radii.sm,
								paddingVertical: spacing.sm,
							},
							pressed && styles.pressed,
						]}
					>
						<Text style={[styles.cancelLabel, { color: colors.text }]}>
							{t("common.cancel")}
						</Text>
					</Pressable>
				</View>
			</View>
			{createOpen && (
				<CreateCollectionModal
					visible
					fixedType={type}
					onClose={() => setCreateOpen(false)}
					onCreated={addToCreated}
				/>
			)}
		</Modal>
	);
}

const styles = StyleSheet.create({
	overlay: { flex: 1, justifyContent: "flex-end" },
	sheet: { width: "100%" },
	title: { fontSize: 18, fontWeight: "700" },
	list: { maxHeight: 320 },
	message: { alignItems: "flex-start" },
	retry: {
		minHeight: 44,
		justifyContent: "center",
		paddingHorizontal: 8,
	},
	collectionRow: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "flex-start",
		minHeight: 44,
		gap: 10,
	},
	collectionName: { fontSize: 15, fontWeight: "600" },
	create: {
		borderWidth: 1,
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		gap: 6,
		minHeight: 44,
	},
	cancel: {
		borderWidth: 1,
		alignItems: "center",
		justifyContent: "center",
		minHeight: 44,
	},
	cancelLabel: { fontSize: 15, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

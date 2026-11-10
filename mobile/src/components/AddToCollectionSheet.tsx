import Ionicons from "@expo/vector-icons/Ionicons";
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
	isAlreadyInCollection,
	useAddVideoToCollection,
	useVideoCollections,
} from "../api/collections";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface AddToCollectionSheetProps {
	visible: boolean;
	mediaId: number;
	onClose: () => void;
}

// Минимальный bottom sheet Task 7: только выбор существующей видеоколлекции.
// Создание коллекции и переносы — Task 17, поэтому кнопки «создать» здесь нет.
export function AddToCollectionSheet({
	visible,
	mediaId,
	onClose,
}: AddToCollectionSheetProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const insets = useSafeAreaInsets();
	const collections = useVideoCollections();
	const add = useAddVideoToCollection();
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
	cancel: {
		borderWidth: 1,
		alignItems: "center",
		justifyContent: "center",
		minHeight: 44,
	},
	cancelLabel: { fontSize: 15, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

import type { Collection, Media } from "@flux/shared";
import {
	ActivityIndicator,
	Modal,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

export type ConfirmTarget =
	| { kind: "empty" }
	| { kind: "media"; media: Media }
	| { kind: "collection"; collection: Collection };

// Подтверждение необратимых операций: purge строки/коллекции и полная
// очистка корзины. Restore подтверждения не требует.
export function TrashConfirmModal({
	target,
	pending,
	onCancel,
	onConfirm,
}: {
	target: ConfirmTarget;
	pending: boolean;
	onCancel: () => void;
	onConfirm: () => void;
}) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();

	let title = t("trash.emptyTitle");
	let body = t("trash.emptyConfirm");
	let actionLabel = t("trash.emptyAction");
	if (target.kind === "media") {
		title = t("trash.purgeTitle");
		body = t("trash.purgeMediaConfirm", { title: target.media.title });
		actionLabel = t("trash.purge");
	} else if (target.kind === "collection") {
		title = t("trash.purgeTitle");
		body = t("trash.purgeCollectionConfirm", { name: target.collection.name });
		actionLabel = t("trash.purge");
	}

	return (
		<Modal visible transparent animationType="fade" onRequestClose={onCancel}>
			<View style={styles.overlay}>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.close")}
					onPress={onCancel}
					testID="trash-confirm-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="trash-confirm-modal"
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
					<Text
						testID="trash-confirm-body"
						style={[styles.body, { color: colors.text }]}
					>
						{body}
					</Text>
					<View style={[styles.actions, { gap: spacing.sm }]}>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.cancel")}
							onPress={onCancel}
							testID="trash-confirm-cancel"
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
							accessibilityLabel={actionLabel}
							accessibilityState={{ disabled: pending }}
							disabled={pending}
							onPress={onConfirm}
							testID="trash-confirm-submit"
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
							{pending ? (
								<ActivityIndicator size="small" color={colors.onAccent} />
							) : (
								<Text style={[styles.buttonLabel, { color: colors.onAccent }]}>
									{actionLabel}
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

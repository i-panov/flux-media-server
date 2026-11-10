import type { Collection } from "@flux/shared";
import { useState } from "react";
import {
	ActivityIndicator,
	KeyboardAvoidingView,
	Modal,
	Platform,
	Pressable,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import { useRenameCollection } from "../api/collections";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface RenameCollectionModalProps {
	visible: boolean;
	collection: Collection;
	onClose: () => void;
}

export function RenameCollectionModal({
	visible,
	collection,
	onClose,
}: RenameCollectionModalProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const [name, setName] = useState(collection.name);
	const rename = useRenameCollection();
	const trimmed = name.trim();
	const canSave = trimmed !== "" && !rename.isPending;

	const submit = () => {
		if (!canSave) {
			return;
		}
		rename.mutate({ id: collection.id, name: trimmed }, { onSuccess: onClose });
	};

	return (
		<Modal
			visible={visible}
			transparent
			animationType="fade"
			onRequestClose={onClose}
		>
			<KeyboardAvoidingView
				behavior={Platform.OS === "ios" ? "padding" : "height"}
				style={styles.overlay}
			>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.close")}
					onPress={onClose}
					testID="collection-rename-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="collection-rename-modal"
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
						{t("collections.renameTitle")}
					</Text>
					<TextInput
						testID="collection-rename-input"
						accessibilityLabel={t("collections.name")}
						autoFocus
						selectTextOnFocus
						value={name}
						onChangeText={(next) => {
							setName(next);
							if (rename.isError) {
								rename.reset();
							}
						}}
						onSubmitEditing={submit}
						returnKeyType="done"
						maxLength={200}
						placeholder={t("collections.namePlaceholder")}
						placeholderTextColor={colors.textMuted}
						style={[
							styles.input,
							{
								borderColor: colors.controlBorder,
								borderRadius: radii.sm,
								color: colors.text,
								backgroundColor: colors.background,
								paddingHorizontal: spacing.md,
							},
						]}
					/>
					{rename.isError && (
						<Text
							testID="collection-rename-error"
							accessibilityRole="alert"
							style={[styles.error, { color: colors.danger }]}
						>
							{t("collections.renameError")}
						</Text>
					)}
					<View style={[styles.actions, { gap: spacing.sm }]}>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.cancel")}
							onPress={onClose}
							testID="collection-rename-cancel"
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
							accessibilityLabel={t("common.save")}
							accessibilityState={{ disabled: !canSave }}
							disabled={!canSave}
							onPress={submit}
							testID="collection-rename-save"
							style={({ pressed }) => [
								styles.button,
								{
									backgroundColor: canSave
										? colors.accent
										: colors.surfaceMuted,
									borderColor: canSave ? colors.accent : colors.border,
									borderRadius: radii.sm,
									paddingHorizontal: spacing.md,
								},
								pressed && styles.pressed,
							]}
						>
							{rename.isPending ? (
								<ActivityIndicator size="small" color={colors.textMuted} />
							) : (
								<Text
									style={[
										styles.buttonLabel,
										{ color: canSave ? colors.onAccent : colors.textMuted },
									]}
								>
									{t("common.save")}
								</Text>
							)}
						</Pressable>
					</View>
				</View>
			</KeyboardAvoidingView>
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
	input: { minHeight: 44, borderWidth: 1, fontSize: 16 },
	error: { fontSize: 13, lineHeight: 18 },
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

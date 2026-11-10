import { ApiError } from "@flux/shared";
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
import { useRenameArtist } from "../api/metadata";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface RenameArtistModalProps {
	artistId: number;
	initialName: string;
	visible: boolean;
	onClose: () => void;
}

// Модалка монтируется только на время открытия, поэтому имя стартует с
// текущего и не затирается фоновыми рефетчами справочника.
export function RenameArtistModal({
	artistId,
	initialName,
	visible,
	onClose,
}: RenameArtistModalProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const [name, setName] = useState(initialName);
	const rename = useRenameArtist();
	const trimmed = name.trim();
	const canSave = trimmed !== "" && !rename.isPending;

	const submit = () => {
		if (!canSave) {
			return;
		}
		rename.mutate({ id: artistId, name: trimmed }, { onSuccess: onClose });
	};

	const errorText =
		rename.error instanceof ApiError && rename.error.status === 409
			? t("artists.nameTaken")
			: t("artists.renameError");

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
					testID="artist-rename-backdrop"
					style={[StyleSheet.absoluteFill, { backgroundColor: colors.overlay }]}
				/>
				<View
					testID="artist-rename-modal"
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
						{t("artists.renameTitle")}
					</Text>
					<TextInput
						testID="artist-rename-input"
						accessibilityLabel={t("artists.name")}
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
						placeholder={t("artists.name")}
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
							testID="artist-rename-error"
							accessibilityRole="alert"
							style={[styles.error, { color: colors.danger }]}
						>
							{errorText}
						</Text>
					)}
					<View style={[styles.actions, { gap: spacing.sm }]}>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.cancel")}
							onPress={onClose}
							testID="artist-rename-cancel"
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
							testID="artist-rename-save"
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

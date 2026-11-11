import Ionicons from "@expo/vector-icons/Ionicons";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	TextInput,
	type TextInputProps,
	View,
} from "react-native";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface EditHeaderProps {
	title: string;
	onBack: () => void;
	saving: boolean;
	canSave: boolean;
	onSave?: () => void;
}

// Шапка общая для формы, загрузки, 404 и admin-only: на узких экранах
// кнопка сохранения остаётся в одну строку с заголовком.
export function EditHeader({
	title,
	onBack,
	saving,
	canSave,
	onSave,
}: EditHeaderProps) {
	const { colors, radii, spacing } = useTheme();
	return (
		<View style={[styles.header, { gap: spacing.sm }]}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={onBack}
				testID="metadata-edit-back"
				hitSlop={8}
				style={({ pressed }) => [
					styles.headerButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.accent} />
			</Pressable>
			<Text style={[styles.headerTitle, { color: colors.text }]}>{title}</Text>
			{onSave === undefined ? (
				<View style={styles.headerButton} />
			) : (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.save")}
					accessibilityState={{ disabled: !canSave, busy: saving }}
					disabled={!canSave}
					onPress={onSave}
					testID="metadata-save"
					hitSlop={4}
					style={({ pressed }) => [
						styles.saveButton,
						{
							backgroundColor: colors.accent,
							borderRadius: radii.sm,
							paddingHorizontal: spacing.md,
						},
						(!canSave || saving) && styles.disabled,
						pressed && styles.pressed,
					]}
				>
					{saving ? (
						<ActivityIndicator size="small" color={colors.onAccent} />
					) : (
						<Text style={[styles.saveLabel, { color: colors.onAccent }]}>
							{t("common.save")}
						</Text>
					)}
				</Pressable>
			)}
		</View>
	);
}

interface MetadataFieldProps {
	label: string;
	value: string;
	onChangeText: (value: string) => void;
	testID: string;
	editable: boolean;
	required?: boolean;
	hint?: string;
	error?: string;
	placeholder?: string;
	multiline?: boolean;
	keyboardType?: TextInputProps["keyboardType"];
	autoCapitalize?: TextInputProps["autoCapitalize"];
	autoCorrect?: boolean;
}

export function MetadataField({
	label,
	value,
	onChangeText,
	testID,
	editable,
	required = false,
	hint,
	error,
	placeholder,
	multiline = false,
	keyboardType,
	autoCapitalize,
	autoCorrect,
}: MetadataFieldProps) {
	const { colors, radii, spacing } = useTheme();
	return (
		<View style={{ gap: spacing.xs }}>
			<Text style={[styles.label, { color: colors.text }]}>
				{required ? `${label} *` : label}
			</Text>
			<TextInput
				accessibilityLabel={label}
				value={value}
				onChangeText={onChangeText}
				editable={editable}
				multiline={multiline}
				placeholder={placeholder}
				placeholderTextColor={colors.textMuted}
				selectionColor={colors.accent}
				keyboardType={keyboardType}
				autoCapitalize={autoCapitalize}
				autoCorrect={autoCorrect}
				textAlignVertical={multiline ? "top" : "center"}
				testID={testID}
				style={[
					styles.input,
					{
						minHeight: multiline ? 96 : 44,
						backgroundColor: colors.surface,
						borderColor: colors.controlBorder,
						borderRadius: radii.sm,
						color: colors.text,
						padding: spacing.sm,
					},
				]}
			/>
			{error === undefined ? (
				hint === undefined ? null : (
					<Text style={[styles.hint, { color: colors.textMuted }]}>{hint}</Text>
				)
			) : (
				<Text
					accessibilityRole="alert"
					accessibilityLiveRegion="polite"
					style={[styles.fieldError, { color: colors.danger }]}
				>
					{error}
				</Text>
			)}
		</View>
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
	headerTitle: { flex: 1, fontSize: 20, fontWeight: "700" },
	saveButton: {
		minHeight: 44,
		minWidth: 88,
		alignItems: "center",
		justifyContent: "center",
	},
	saveLabel: { fontSize: 15, fontWeight: "600" },
	label: { fontSize: 14, fontWeight: "600" },
	input: { borderWidth: 1, fontSize: 16 },
	hint: { fontSize: 12, lineHeight: 16 },
	fieldError: { fontSize: 12, lineHeight: 16 },
	disabled: { opacity: 0.5 },
	pressed: { opacity: 0.7 },
});

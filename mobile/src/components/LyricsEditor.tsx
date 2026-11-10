import Ionicons from "@expo/vector-icons/Ionicons";
import type { SaveLyricsInput } from "@flux/shared";
import { useState } from "react";
import {
	ActivityIndicator,
	Alert,
	KeyboardAvoidingView,
	Modal,
	Platform,
	Pressable,
	ScrollView,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

export interface LyricsDraft {
	lyricsText: string;
	translation: string;
	syncData: string;
	source: string;
}

interface LyricsEditorProps {
	initial: LyricsDraft;
	/** Есть сохранённые данные: только тогда пустая отправка = очистка. */
	hasExisting: boolean;
	saving: boolean;
	onCancel: () => void;
	onSave: (input: SaveLyricsInput) => void;
}

interface FieldProps {
	label: string;
	value: string;
	placeholder: string;
	testID: string;
	onChangeText: (value: string) => void;
	editable: boolean;
	minHeight: number;
	hint?: string;
	mono?: boolean;
}

function EditorField({
	label,
	value,
	placeholder,
	testID,
	onChangeText,
	editable,
	minHeight,
	hint,
	mono = false,
}: FieldProps) {
	const { colors, radii, spacing } = useTheme();
	return (
		<View style={{ gap: spacing.xs }}>
			<Text style={[styles.label, { color: colors.text }]}>{label}</Text>
			<TextInput
				accessibilityLabel={label}
				value={value}
				onChangeText={onChangeText}
				editable={editable}
				multiline
				placeholder={placeholder}
				placeholderTextColor={colors.textMuted}
				selectionColor={colors.accent}
				textAlignVertical="top"
				testID={testID}
				style={[
					styles.input,
					{
						minHeight,
						backgroundColor: colors.surface,
						borderColor: colors.controlBorder,
						borderRadius: radii.sm,
						color: colors.text,
						padding: spacing.sm,
					},
					mono && styles.mono,
				]}
			/>
			{hint === undefined ? null : (
				<Text style={[styles.hint, { color: colors.textMuted }]}>{hint}</Text>
			)}
		</View>
	);
}

// Минимальный админский редактор: три обычных TextInput вместо rich-editor.
// Пустые все поля — осознанная очистка через подтверждение (clear:true в
// shared saveLyrics), иначе пустое поле сохраняется как есть.
export function LyricsEditor({
	initial,
	hasExisting,
	saving,
	onCancel,
	onSave,
}: LyricsEditorProps) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const [lyricsText, setLyricsText] = useState(initial.lyricsText);
	const [translation, setTranslation] = useState(initial.translation);
	const [syncData, setSyncData] = useState(initial.syncData);
	const cancelLabel = t("common.cancel");

	// Пока идёт сохранение, закрывать редактор нельзя: иначе результат
	// мутации придёт в уже размонтированный экран.
	const cancel = () => {
		if (!saving) {
			onCancel();
		}
	};

	const submit = () => {
		onSave({
			lyricsText,
			translation,
			syncData,
			source: initial.source === "" ? "user" : initial.source,
		});
	};

	const save = () => {
		const empty =
			lyricsText.trim() === "" &&
			translation.trim() === "" &&
			syncData.trim() === "";
		if (!empty) {
			submit();
			return;
		}
		if (!hasExisting) {
			Alert.alert(
				t("audio.lyrics.nothingToSave"),
				t("audio.lyrics.nothingToSaveHint"),
			);
			return;
		}
		Alert.alert(t("audio.lyrics.clearTitle"), t("audio.lyrics.clearConfirm"), [
			{ text: cancelLabel, style: "cancel" },
			{
				text: t("audio.lyrics.clearAction"),
				style: "destructive",
				onPress: submit,
			},
		]);
	};

	return (
		<Modal visible animationType="slide" onRequestClose={cancel}>
			<SafeAreaView
				edges={["top", "bottom"]}
				testID="lyrics-editor"
				style={[styles.safe, { backgroundColor: colors.background }]}
			>
				<KeyboardAvoidingView
					behavior={Platform.OS === "ios" ? "padding" : undefined}
					style={styles.fill}
				>
					<View
						style={[
							styles.header,
							{
								borderBottomColor: colors.border,
								padding: spacing.md,
							},
						]}
					>
						<Text style={[styles.title, { color: colors.text }]}>
							{t("audio.lyrics.editorTitle")}
						</Text>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("common.close")}
							accessibilityState={{ disabled: saving }}
							disabled={saving}
							onPress={cancel}
							testID="lyrics-editor-close"
							hitSlop={8}
							style={({ pressed }) => [
								styles.headerButton,
								(pressed || saving) && styles.pressed,
							]}
						>
							<Ionicons name="close" size={24} color={colors.text} />
						</Pressable>
					</View>
					<ScrollView
						style={styles.fill}
						contentContainerStyle={[
							styles.content,
							{ padding: spacing.lg, gap: spacing.md },
						]}
						keyboardShouldPersistTaps="handled"
					>
						<EditorField
							label={t("audio.lyrics.textLabel")}
							value={lyricsText}
							placeholder={t("audio.lyrics.textPlaceholder")}
							testID="lyrics-editor-text"
							onChangeText={setLyricsText}
							editable={!saving}
							minHeight={180}
						/>
						<EditorField
							label={t("audio.lyrics.translationLabel")}
							value={translation}
							placeholder={t("audio.lyrics.translationPlaceholder")}
							testID="lyrics-editor-translation"
							onChangeText={setTranslation}
							editable={!saving}
							minHeight={140}
							hint={t("audio.lyrics.translationHint")}
						/>
						<EditorField
							label={t("audio.lyrics.syncLabel")}
							value={syncData}
							placeholder={"[00:12.00] "}
							testID="lyrics-editor-sync"
							onChangeText={setSyncData}
							editable={!saving}
							minHeight={120}
							hint={t("audio.lyrics.syncHint")}
							mono
						/>
					</ScrollView>
					<View
						style={[
							styles.footer,
							{
								borderTopColor: colors.border,
								padding: spacing.md,
								gap: spacing.sm,
							},
						]}
					>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={cancelLabel}
							accessibilityState={{ disabled: saving }}
							disabled={saving}
							onPress={cancel}
							testID="lyrics-editor-cancel"
							style={({ pressed }) => [
								styles.footerButton,
								{ borderColor: colors.borderStrong },
								(pressed || saving) && styles.pressed,
							]}
						>
							<Text style={[styles.footerLabel, { color: colors.text }]}>
								{cancelLabel}
							</Text>
						</Pressable>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={t("audio.lyrics.save")}
							accessibilityState={{ disabled: saving, busy: saving }}
							disabled={saving}
							onPress={save}
							testID="lyrics-editor-save"
							style={({ pressed }) => [
								styles.footerButton,
								styles.saveButton,
								{ backgroundColor: colors.accent },
								(pressed || saving) && styles.pressed,
							]}
						>
							{saving ? (
								<ActivityIndicator color={colors.onAccent} />
							) : (
								<Text style={[styles.footerLabel, { color: colors.onAccent }]}>
									{t("audio.lyrics.save")}
								</Text>
							)}
						</Pressable>
					</View>
				</KeyboardAvoidingView>
			</SafeAreaView>
		</Modal>
	);
}

const styles = StyleSheet.create({
	safe: { flex: 1 },
	fill: { flex: 1 },
	header: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		borderBottomWidth: 1,
	},
	headerButton: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	title: { fontSize: 18, fontWeight: "700" },
	content: { paddingBottom: 32 },
	label: { fontSize: 14, fontWeight: "600" },
	input: { borderWidth: 1, fontSize: 15, lineHeight: 21 },
	mono: { fontFamily: Platform.select({ ios: "Menlo", default: "monospace" }) },
	hint: { fontSize: 12, lineHeight: 16 },
	footer: { flexDirection: "row", borderTopWidth: 1 },
	footerButton: {
		flex: 1,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
		borderWidth: 1,
		borderRadius: 8,
	},
	saveButton: { borderWidth: 0 },
	footerLabel: { fontSize: 15, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

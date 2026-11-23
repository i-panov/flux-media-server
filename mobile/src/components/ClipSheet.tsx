import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { useState } from "react";
import {
	ActivityIndicator,
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
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useCancelClip, useClip, useCreateClip } from "../api/clip";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

// Обрезка видео: маркеры ставятся по текущей позиции плеера, границы
// можно поправить вручную. Оригинал не меняется — создаётся фрагмент.
export function ClipSheet({
	media,
	position,
	duration,
	onClose,
}: {
	media: Media;
	position: number;
	duration: number;
	onClose: () => void;
}) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const insets = useSafeAreaInsets();
	const create = useCreateClip();
	const cancel = useCancelClip();
	const [start, setStart] = useState("0");
	const [end, setEnd] = useState(
		duration > 0 ? String(Math.floor(duration)) : "",
	);
	const [title, setTitle] = useState("");
	const [jobID, setJobID] = useState<number | null>(null);
	const [error, setError] = useState<string | null>(null);
	const job = useClip(jobID);

	const submit = () => {
		const from = Number(start);
		const to = Number(end);
		if (!Number.isFinite(from) || !Number.isFinite(to) || to <= from) {
			setError(t("clip.rangeError"));
			return;
		}
		setError(null);
		create.mutate(
			{
				mediaID: media.id,
				start: from,
				end: to,
				title: title.trim() || undefined,
			},
			{
				onSuccess: (task) => setJobID(task.id),
				onError: () => setError(t("clip.error")),
			},
		);
	};

	const status = job.data?.status;
	const running = status === "queued" || status === "processing";
	return (
		<Modal visible transparent animationType="slide" onRequestClose={onClose}>
			<KeyboardAvoidingView
				style={styles.backdrop}
				behavior={Platform.OS === "ios" ? "padding" : undefined}
			>
				<Pressable style={styles.backdrop} onPress={onClose}>
					<Pressable
						onPress={() => undefined}
						style={[
							styles.sheet,
							{
								backgroundColor: colors.surface,
								borderRadius: radii.lg,
								padding: spacing.lg,
								paddingBottom: spacing.lg + insets.bottom,
								gap: spacing.sm,
							},
						]}
					>
						<ScrollView
							keyboardShouldPersistTaps="handled"
							contentContainerStyle={{ gap: spacing.sm }}
						>
							<View style={[styles.row, styles.between]}>
								<Text
									style={{
										color: colors.text,
										fontSize: 18,
										fontWeight: "600",
									}}
								>
									{t("clip.title")}
								</Text>
								<Pressable onPress={onClose} testID="clip-close">
									<Ionicons name="close" size={20} color={colors.textMuted} />
								</Pressable>
							</View>
							<Text style={{ color: colors.textMuted }}>
								{t("clip.position", { value: position.toFixed(1) })}
							</Text>
							<View style={[styles.row, { gap: spacing.sm }]}>
								<TimeField
									testID="clip-start"
									label={t("clip.start")}
									value={start}
									onChange={setStart}
								/>
								<TimeField
									testID="clip-end"
									label={t("clip.end")}
									value={end}
									onChange={setEnd}
								/>
							</View>
							<TextInput
								value={title}
								onChangeText={setTitle}
								placeholder={t("clip.name")}
								placeholderTextColor={colors.textMuted}
								testID="clip-title"
								style={[
									styles.input,
									{
										color: colors.text,
										borderColor: colors.border,
										borderRadius: radii.md,
									},
								]}
							/>
							{error !== null && (
								<Text style={{ color: colors.danger }}>{error}</Text>
							)}
							{status !== undefined && (
								<Text style={{ color: colors.textMuted }}>
									{status === "done"
										? t("clip.done")
										: status === "error"
											? t("clip.error")
											: t("clip.progress")}
								</Text>
							)}
							{running && jobID !== null && (
								<Pressable
									testID="clip-cancel"
									onPress={() => cancel.mutate(jobID)}
								>
									<Text style={{ color: colors.danger }}>
										{t("clip.cancel")}
									</Text>
								</Pressable>
							)}
							<Pressable
								testID="clip-submit"
								disabled={create.isPending || running}
								onPress={submit}
								style={[
									styles.button,
									{ backgroundColor: colors.accent, borderRadius: radii.md },
								]}
							>
								{create.isPending ? (
									<ActivityIndicator color={colors.onAccent} />
								) : (
									<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
										{t("clip.submit")}
									</Text>
								)}
							</Pressable>
						</ScrollView>
					</Pressable>
				</Pressable>
			</KeyboardAvoidingView>
		</Modal>
	);
}

function TimeField({
	testID,
	label,
	value,
	onChange,
}: {
	testID: string;
	label: string;
	value: string;
	onChange: (value: string) => void;
}) {
	const { colors, radii } = useTheme();
	return (
		<View style={{ flex: 1, gap: 4 }}>
			<Text style={{ color: colors.textMuted }}>{label}</Text>
			<TextInput
				value={value}
				onChangeText={onChange}
				keyboardType="numeric"
				testID={testID}
				style={[
					styles.input,
					{
						color: colors.text,
						borderColor: colors.border,
						borderRadius: radii.md,
					},
				]}
			/>
		</View>
	);
}

const styles = StyleSheet.create({
	backdrop: {
		flex: 1,
		backgroundColor: "rgba(0,0,0,0.4)",
		justifyContent: "flex-end",
	},
	sheet: { maxHeight: "90%" },
	row: { flexDirection: "row", alignItems: "center" },
	between: { justifyContent: "space-between" },
	small: { borderWidth: 1, paddingHorizontal: 10, paddingVertical: 8 },
	input: { borderWidth: 1, paddingHorizontal: 10, paddingVertical: 8 },
	button: { alignItems: "center", paddingVertical: 12 },
});

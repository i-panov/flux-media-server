/* eslint-disable max-lines-per-function -- карточка формы, статуса и отмены загрузки. */
import Ionicons from "@expo/vector-icons/Ionicons";
import { useEffect, useState } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import {
	cancelMediaLoaderJob,
	fetchMediaLoaderJob,
	type MediaLoaderJob,
	startMediaLoader,
} from "../api/mediaLoader";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

const VIDEO_FORMATS = ["mp4", "mkv"];
const AUDIO_FORMATS = ["mp3", "m4a", "opus"];
const QUALITIES = ["max", "1080p", "720p", "480p"];

const TERMINAL = new Set(["done", "error", "cancelled"]);

export function LinkDownloadCard({
	type,
}: {
	type: "video" | "audio" | "image";
}) {
	const { colors, radii, spacing } = useTheme();
	const [url, setUrl] = useState("");
	const [format, setFormat] = useState(type === "audio" ? "mp3" : "mp4");
	const [quality, setQuality] = useState("max");
	const [job, setJob] = useState<MediaLoaderJob | null>(null);
	const [starting, setStarting] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const active = job !== null && !TERMINAL.has(job.status);

	useEffect(() => {
		if (job === null || TERMINAL.has(job.status)) {
			return;
		}
		let cancelled = false;
		const id = job.id;
		const timer = setInterval(() => {
			void fetchMediaLoaderJob(id)
				.then((next) => {
					if (!cancelled) setJob(next);
				})
				.catch(() => {
					if (!cancelled) setError(t("upload.link.failed"));
				});
		}, 2000);
		return () => {
			cancelled = true;
			clearInterval(timer);
		};
	}, [job]);

	if (type === "image") {
		return null;
	}

	const submit = async (): Promise<void> => {
		const trimmed = url.trim();
		if (trimmed === "" || starting) return;
		setError(null);
		setStarting(true);
		try {
			const created = await startMediaLoader({
				url: trimmed,
				audioOnly: type === "audio",
				format,
				quality,
			});
			setJob(created);
		} catch (cause) {
			setError(
				cause instanceof Error ? cause.message : t("upload.link.failed"),
			);
		} finally {
			setStarting(false);
		}
	};

	const cancel = (): void => {
		if (job !== null) {
			void cancelMediaLoaderJob(job.id).catch(() => undefined);
			setJob({ ...job, status: "cancelled" });
		}
	};

	const formats = type === "audio" ? AUDIO_FORMATS : VIDEO_FORMATS;
	return (
		<View
			testID="upload-link-card"
			style={[
				styles.card,
				{
					borderColor: colors.border,
					backgroundColor: colors.surface,
					borderRadius: radii.md,
					padding: spacing.md,
					gap: spacing.sm,
				},
			]}
		>
			<View style={[styles.titleRow, { gap: spacing.xs }]}>
				<Ionicons name="link-outline" size={18} color={colors.accent} />
				<Text style={[styles.title, { color: colors.text }]}>
					{t("upload.link.title")}
				</Text>
			</View>
			<Text style={[styles.hint, { color: colors.textMuted }]}>
				{t("upload.link.hint")}
			</Text>
			<TextInput
				testID="upload-link-url"
				value={url}
				onChangeText={setUrl}
				placeholder="https://..."
				placeholderTextColor={colors.textMuted}
				autoCapitalize="none"
				autoCorrect={false}
				keyboardType="url"
				editable={!starting && !active}
				style={[
					styles.input,
					{
						borderColor: colors.borderStrong,
						color: colors.text,
						borderRadius: radii.sm,
						paddingHorizontal: spacing.sm,
					},
				]}
			/>
			<Text style={[styles.label, { color: colors.textMuted }]}>
				{t("upload.link.format")}
			</Text>
			<View style={[styles.pills, { gap: spacing.xs }]}>
				{formats.map((value) => (
					<Pressable
						key={value}
						accessibilityRole="button"
						accessibilityState={{ selected: format === value }}
						onPress={() => setFormat(value)}
						style={[
							styles.pill,
							{
								borderColor: format === value ? colors.accent : colors.border,
								backgroundColor:
									format === value ? colors.surfaceMuted : colors.surface,
								borderRadius: radii.pill,
								paddingHorizontal: spacing.sm,
							},
						]}
					>
						<Text
							style={{ color: format === value ? colors.accent : colors.text }}
						>
							{value.toUpperCase()}
						</Text>
					</Pressable>
				))}
			</View>
			{type === "video" && (
				<>
					<Text style={[styles.label, { color: colors.textMuted }]}>
						{t("upload.link.quality")}
					</Text>
					<View style={[styles.pills, { gap: spacing.xs }]}>
						{QUALITIES.map((value) => (
							<Pressable
								key={value}
								accessibilityRole="button"
								accessibilityState={{ selected: quality === value }}
								onPress={() => setQuality(value)}
								style={[
									styles.pill,
									{
										borderColor:
											quality === value ? colors.accent : colors.border,
										backgroundColor:
											quality === value ? colors.surfaceMuted : colors.surface,
										borderRadius: radii.pill,
										paddingHorizontal: spacing.sm,
									},
								]}
							>
								<Text
									style={{
										color: quality === value ? colors.accent : colors.text,
									}}
								>
									{value === "max" ? "MAX" : value}
								</Text>
							</Pressable>
						))}
					</View>
				</>
			)}
			<Pressable
				accessibilityRole="button"
				testID="upload-link-submit"
				disabled={starting || active || url.trim() === ""}
				onPress={() => void submit()}
				style={[
					styles.submit,
					{
						backgroundColor: colors.accent,
						borderRadius: radii.md,
						paddingHorizontal: spacing.md,
					},
					(starting || active || url.trim() === "") && styles.pressed,
				]}
			>
				{starting ? (
					<ActivityIndicator color={colors.onAccent} />
				) : (
					<Ionicons name="download-outline" size={18} color={colors.onAccent} />
				)}
				<Text style={[styles.submitText, { color: colors.onAccent }]}>
					{t("upload.link.submit")}
				</Text>
			</Pressable>
			{error !== null && (
				<Text accessibilityRole="alert" style={{ color: colors.danger }}>
					{error}
				</Text>
			)}
			{job !== null && (
				<View
					testID="upload-link-status"
					style={[
						styles.status,
						{
							borderColor: colors.border,
							borderRadius: radii.sm,
							padding: spacing.sm,
							gap: spacing.xs,
						},
					]}
				>
					<View style={styles.statusRow}>
						<Text style={[styles.statusText, { color: colors.text }]}>
							{job.title ?? job.filename ?? t("upload.link.title")}
						</Text>
						{active && (
							<Pressable
								accessibilityRole="button"
								onPress={cancel}
								hitSlop={8}
							>
								<Text style={{ color: colors.danger }}>
									{t("upload.link.cancel")}
								</Text>
							</Pressable>
						)}
					</View>
					<Text style={{ color: colors.textMuted }}>
						{t(`upload.link.status.${job.status}`)}
						{job.stage !== undefined && job.stage !== ""
							? ` · ${job.stage}`
							: ""}
					</Text>
					{job.error !== undefined && (
						<Text style={{ color: colors.danger }}>{job.error}</Text>
					)}
				</View>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	card: { borderWidth: 1 },
	titleRow: { flexDirection: "row", alignItems: "center" },
	title: { fontSize: 16, fontWeight: "700" },
	hint: { fontSize: 13 },
	label: { fontSize: 12, fontWeight: "600" },
	input: { minHeight: 44, borderWidth: 1 },
	pills: { flexDirection: "row", flexWrap: "wrap" },
	pill: { minHeight: 36, borderWidth: 1, justifyContent: "center" },
	submit: {
		minHeight: 44,
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "center",
		gap: 8,
	},
	submitText: { fontSize: 15, fontWeight: "600" },
	status: { borderWidth: 1 },
	statusRow: { flexDirection: "row", justifyContent: "space-between", gap: 8 },
	statusText: { flex: 1, fontWeight: "600" },
	pressed: { opacity: 0.6 },
});

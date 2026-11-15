/* eslint-disable max-lines-per-function -- карточка формы и списка заданий. */
import Ionicons from "@expo/vector-icons/Ionicons";
import { useQueryClient } from "@tanstack/react-query";
import { useEffect, useRef, useState } from "react";
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
	fetchMediaLoaderJobs,
	type MediaLoaderJob,
	startMediaLoader,
} from "../api/mediaLoader";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

const VIDEO_FORMATS = ["mp4", "mkv"];
const AUDIO_FORMATS = ["mp3", "m4a", "opus"];
const QUALITIES = ["max", "1080p", "720p", "480p"];
const TERMINAL = new Set(["done", "error", "cancelled"]);

function activeJob(job: MediaLoaderJob): boolean {
	return !TERMINAL.has(job.status);
}

function JobCard({
	job,
	onCancel,
}: {
	job: MediaLoaderJob;
	onCancel: (id: string) => void;
}) {
	const { colors, radii, spacing } = useTheme();
	const active = activeJob(job);
	return (
		<View
			testID={`upload-link-job-${job.id}`}
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
						onPress={() => onCancel(job.id)}
						hitSlop={8}
					>
						<Text style={{ color: colors.danger }}>
							{t("upload.link.cancel")}
						</Text>
					</Pressable>
				)}
			</View>
			{job.status === "importing" || job.status === "processing" ? (
				<View style={[styles.statusRow, { gap: spacing.xs }]}>
					<ActivityIndicator size="small" color={colors.accent} />
					<Text style={{ color: colors.textMuted }}>
						{t(`upload.link.status.${job.status}`)}
					</Text>
				</View>
			) : (
				<Text style={{ color: colors.textMuted }}>
					{t(`upload.link.status.${job.status}`)}
					{job.stage !== undefined && job.stage !== "" ? ` · ${job.stage}` : ""}
				</Text>
			)}
			{job.status === "downloading" && job.progress !== undefined && (
				<View style={[styles.progressRow, { gap: spacing.xs }]}>
					<View
						testID="upload-link-progress"
						style={[
							styles.progressTrack,
							{
								backgroundColor: colors.surfaceMuted,
								borderRadius: radii.pill,
							},
						]}
					>
						<View
							style={[
								styles.progressFill,
								{
									width: `${Math.max(0, Math.min(100, job.progress))}%`,
									backgroundColor: colors.accent,
									borderRadius: radii.pill,
								},
							]}
						/>
					</View>
					<Text style={{ color: colors.textMuted }}>
						{Math.round(job.progress)}%
					</Text>
				</View>
			)}
			{job.error !== undefined && (
				<Text style={{ color: colors.danger }}>{job.error}</Text>
			)}
		</View>
	);
}

export function LinkDownloadCard({
	type,
}: {
	type: "video" | "audio" | "image";
}) {
	const { colors, radii, spacing } = useTheme();
	const [url, setUrl] = useState("");
	const [format, setFormat] = useState(type === "audio" ? "mp3" : "mp4");
	const [quality, setQuality] = useState("max");
	const [jobs, setJobs] = useState<MediaLoaderJob[]>([]);
	const [starting, setStarting] = useState(false);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState<string | null>(null);
	const queryClient = useQueryClient();
	const hasActive = jobs.some(activeJob);
	// Завершённые задания backend уже не отдаёт в списке. Переход
	// «было активным → исчезло из списка» означает, что медиа появилось
	// в библиотеке; инвалидируем грид, иначе он ждёт рестарта приложения.
	const previousActive = useRef<Set<string>>(new Set());
	useEffect(() => {
		const currentActive = new Set(jobs.filter(activeJob).map((job) => job.id));
		let finished = false;
		for (const id of previousActive.current) {
			if (!currentActive.has(id) && !jobs.some((job) => job.id === id)) {
				finished = true;
				break;
			}
		}
		previousActive.current = currentActive;
		if (finished) {
			void queryClient.invalidateQueries({ queryKey: ["media"] });
			void queryClient.invalidateQueries({ queryKey: ["progress"] });
		}
	}, [jobs, queryClient]);

	useEffect(() => {
		let cancelled = false;
		const load = async (): Promise<void> => {
			try {
				const next = await fetchMediaLoaderJobs();
				if (!cancelled) {
					setJobs(next);
					setError(null);
				}
			} catch {
				if (!cancelled) setError(t("upload.link.failed"));
			} finally {
				if (!cancelled) setLoading(false);
			}
		};
		void load();
		if (!hasActive) {
			return () => {
				cancelled = true;
			};
		}
		const timer = setInterval(() => void load(), 2000);
		return () => {
			cancelled = true;
			clearInterval(timer);
		};
	}, [hasActive]);

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
			setJobs((current) => [created, ...current]);
			setUrl("");
		} catch (cause) {
			setError(
				cause instanceof Error ? cause.message : t("upload.link.failed"),
			);
		} finally {
			setStarting(false);
		}
	};

	const cancel = (id: string): void => {
		void cancelMediaLoaderJob(id).catch(() => undefined);
		setJobs((current) =>
			current.map((job) =>
				job.id === id ? { ...job, status: "cancelled" } : job,
			),
		);
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
				editable={!starting}
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
				disabled={starting || url.trim() === ""}
				onPress={() => void submit()}
				style={[
					styles.submit,
					{
						backgroundColor: colors.accent,
						borderRadius: radii.md,
						paddingHorizontal: spacing.md,
					},
					(starting || url.trim() === "") && styles.pressed,
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
			{loading && (
				<View style={[styles.statusRow, { gap: spacing.xs }]}>
					<ActivityIndicator size="small" color={colors.accent} />
					<Text style={{ color: colors.textMuted }}>
						{t("upload.link.starting")}
					</Text>
				</View>
			)}
			{jobs.length > 0 && (
				<View style={{ gap: spacing.xs }}>
					<Text style={[styles.label, { color: colors.textMuted }]}>
						{t("upload.link.queue")}
					</Text>
					{jobs.map((job) => (
						<JobCard key={job.id} job={job} onCancel={cancel} />
					))}
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
	progressRow: { flexDirection: "row", alignItems: "center" },
	progressTrack: { flex: 1, height: 6, overflow: "hidden" },
	progressFill: { height: 6 },
	statusText: { flex: 1, fontWeight: "600" },
	pressed: { opacity: 0.6 },
});

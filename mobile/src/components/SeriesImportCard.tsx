import Ionicons from "@expo/vector-icons/Ionicons";
import { useMemo, useState } from "react";
import {
	ActivityIndicator,
	Pressable,
	ScrollView,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import {
	type ImportJob,
	type ImportProbe,
	useCancelImport,
	useImportJob,
	useImportJobs,
	useImportProbe,
	useStartImport,
} from "../api/importSeries";
import { t, useLanguage } from "../i18n";
import { importScope } from "../import/scope";
import { useTheme } from "../theme/ThemeProvider";

function keyOf(season: number, episode: number): string {
	return `${season}:${episode}`;
}

function ImportJobsList({
	jobs,
	onSelect,
}: {
	jobs: ImportJob[];
	onSelect: (id: number) => void;
}) {
	const { colors } = useTheme();
	return (
		<View style={{ gap: 4 }} testID="import-jobs">
			<Text style={{ color: colors.textMuted }}>{t("import.recent")}</Text>
			{jobs.slice(0, 5).map((item) => (
				<Pressable
					key={item.id}
					testID={`import-job-${item.id}`}
					onPress={() => onSelect(item.id)}
				>
					<Text style={{ color: colors.text }} numberOfLines={1}>
						{item.title || `#${item.id}`} · {item.episodes_done}/
						{item.episodes_total}
					</Text>
				</Pressable>
			))}
		</View>
	);
}

// Импорт сериала по ссылке: сначала проверяем структуру без скачивания,
// затем выбираем серии и показываем прогресс задания.
export function SeriesImportCard() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const [url, setUrl] = useState("");
	const [probe, setProbe] = useState<ImportProbe | null>(null);
	const [selected, setSelected] = useState<string[]>([]);
	const [error, setError] = useState<string | null>(null);
	const [jobID, setJobID] = useState<number | null>(null);
	const probeMutation = useImportProbe();
	const start = useStartImport();
	const cancel = useCancelImport();
	const job = useImportJob(jobID);
	const jobs = useImportJobs();

	const seasons = useMemo(() => {
		const groups = new Map<number, ImportProbe["episodes"]>();
		for (const episode of probe?.episodes ?? []) {
			const list = groups.get(episode.season) ?? [];
			list.push(episode);
			groups.set(episode.season, list);
		}
		return [...groups.entries()].sort((a, b) => a[0] - b[0]);
	}, [probe]);

	const check = () => {
		setError(null);
		setProbe(null);
		setSelected([]);
		probeMutation.mutate(url.trim(), {
			onSuccess: (result) => {
				setProbe(result);
				setSelected(
					result.episodes.map((item) => keyOf(item.season, item.episode)),
				);
			},
			onError: () => setError(t("import.probeError")),
		});
	};

	const startImport = () => {
		if (probe === null) return;
		const episodes = probe.episodes
			.filter((item) => selected.includes(keyOf(item.season, item.episode)))
			.map((item) => ({ season: item.season, episode: item.episode }));
		if (episodes.length === 0) return;
		start.mutate(
			{
				url: url.trim(),
				scope: importScope(probe),
				title: probe.title,
				seriesID: probe.series_id,
				episodes,
			},
			{
				onSuccess: (created) => setJobID(created.id),
				onError: () => setError(t("import.startError")),
			},
		);
	};

	const status = job.data?.job.status;
	const running =
		status === "queued" || status === "downloading" || status === "importing";

	return (
		<View
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
			testID="series-import-card"
		>
			<Text style={{ color: colors.text, fontWeight: "600" }}>
				{t("import.title")}
			</Text>
			<Text style={{ color: colors.textMuted }}>{t("import.hint")}</Text>
			<Text style={{ color: colors.textMuted, fontSize: 12 }}>
				{t("import.limit")}
			</Text>
			<TextInput
				value={url}
				onChangeText={setUrl}
				placeholder={t("import.url")}
				placeholderTextColor={colors.textMuted}
				autoCapitalize="none"
				autoCorrect={false}
				testID="import-url"
				style={[
					styles.input,
					{
						color: colors.text,
						borderColor: colors.border,
						borderRadius: radii.md,
					},
				]}
			/>
			<Pressable
				testID="import-probe"
				disabled={url.trim() === "" || probeMutation.isPending}
				onPress={check}
				style={[
					styles.button,
					{
						backgroundColor: colors.accent,
						borderRadius: radii.md,
						opacity: url.trim() === "" ? 0.5 : 1,
					},
				]}
			>
				{probeMutation.isPending ? (
					<ActivityIndicator color={colors.onAccent} />
				) : (
					<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
						{t("import.probe")}
					</Text>
				)}
			</Pressable>
			{error !== null && <Text style={{ color: colors.danger }}>{error}</Text>}
			{probe !== null && probe.kind === "episode" && (
				<Text style={{ color: colors.textMuted }}>
					{t("import.singleVideo")}
				</Text>
			)}
			{probe !== null && probe.kind === "series" && (
				<View style={{ gap: spacing.sm }}>
					<Text style={{ color: colors.text, fontWeight: "600" }}>
						{probe.title}
					</Text>
					<EpisodeList
						seasons={seasons}
						selected={selected}
						onToggle={(key) =>
							setSelected((prev) =>
								prev.includes(key)
									? prev.filter((value) => value !== key)
									: [...prev, key],
							)
						}
					/>
					<Pressable
						testID="import-start"
						disabled={selected.length === 0 || start.isPending}
						onPress={startImport}
						style={[
							styles.button,
							{
								backgroundColor: colors.accent,
								borderRadius: radii.md,
								opacity: selected.length === 0 ? 0.5 : 1,
							},
						]}
					>
						<Text style={{ color: colors.onAccent, fontWeight: "600" }}>
							{t("import.start", { count: selected.length })}
						</Text>
					</Pressable>
				</View>
			)}
			{jobID !== null && (
				<View style={{ gap: 4 }}>
					<Text style={{ color: colors.text }}>
						{status === "done" || status === "partial"
							? t("import.finished", {
									done: job.data?.job.episodes_done ?? 0,
									total: job.data?.job.episodes_total ?? 0,
								})
							: status === "error"
								? t("import.failed")
								: t("import.running")}
					</Text>
					{running && (
						<Pressable
							testID="import-cancel"
							onPress={() => cancel.mutate(jobID)}
						>
							<Text style={{ color: colors.danger }}>{t("import.cancel")}</Text>
						</Pressable>
					)}
				</View>
			)}
			{jobs.data !== undefined && jobs.data.length > 0 && (
				<ImportJobsList jobs={jobs.data} onSelect={setJobID} />
			)}
		</View>
	);
}

function EpisodeList({
	seasons,
	selected,
	onToggle,
}: {
	seasons: [number, ImportProbe["episodes"]][];
	selected: string[];
	onToggle: (key: string) => void;
}) {
	const { colors, spacing } = useTheme();
	return (
		<ScrollView style={{ maxHeight: 260 }}>
			{seasons.map(([season, episodes]) => (
				<View key={season} style={{ gap: 4 }}>
					<Text style={{ color: colors.textMuted }}>
						{t("import.season", { number: season })}
					</Text>
					{episodes.map((item) => {
						const key = keyOf(item.season, item.episode);
						const checked = selected.includes(key);
						return (
							<Pressable
								key={key}
								testID={`import-episode-${key}`}
								onPress={() => onToggle(key)}
								style={[styles.row, { gap: spacing.sm }]}
							>
								<Ionicons
									name={checked ? "checkbox" : "square-outline"}
									size={18}
									color={checked ? colors.accent : colors.textMuted}
								/>
								<Text style={{ color: colors.text }}>
									S{String(item.season).padStart(2, "0")}E
									{String(item.episode).padStart(2, "0")} · {item.title}
								</Text>
							</Pressable>
						);
					})}
				</View>
			))}
		</ScrollView>
	);
}

const styles = StyleSheet.create({
	card: { borderWidth: 1 },
	row: { flexDirection: "row", alignItems: "center", paddingVertical: 6 },
	input: { borderWidth: 1, paddingHorizontal: 10, paddingVertical: 8 },
	button: { alignItems: "center", paddingVertical: 10 },
});

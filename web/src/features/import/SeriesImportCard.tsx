import {
	Alert,
	Button,
	Card,
	Checkbox,
	Group,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useQueryClient } from "@tanstack/react-query";
import { DownloadCloud } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	type ImportProbe,
	useCancelImport,
	useImportJob,
	useImportJobs,
	useImportProbe,
	useStartImport,
} from "../../api/import";

function keyOf(season: number, episode: number) {
	return `${season}:${episode}`;
}

function ImportProgress({ id }: { id: number }) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const detail = useImportJob(id);
	const jobStatus = detail.data?.job.status;
	useEffect(() => {
		if (jobStatus === "done" || jobStatus === "partial") {
			void queryClient.invalidateQueries({ queryKey: ["works"] });
			void queryClient.invalidateQueries({ queryKey: ["media"] });
		}
	}, [jobStatus, queryClient]);
	if (detail.data === undefined) return null;
	const { job, episodes } = detail.data;
	return (
		<Stack gap={4}>
			<Text size="sm" fw={600}>
				{job.title || `#${job.id}`} · {t(`import.status.${job.status}`)}
			</Text>
			<Text size="xs" c="dimmed">
				{t("import.progress", {
					done: job.episodes_done,
					total: job.episodes_total,
					errors: job.episodes_error,
				})}
			</Text>
			{job.error !== undefined && job.error !== "" && (
				<Text size="xs" c="red">
					{job.error}
				</Text>
			)}
			{episodes.map((episode) => (
				<Text
					key={episode.id}
					size="xs"
					c={episode.status === "error" ? "red" : "dimmed"}
				>
					S{String(episode.season).padStart(2, "0")}E
					{String(episode.episode).padStart(2, "0")} ·{" "}
					{t(`import.episode.${episode.status}`)}
					{episode.error !== undefined && episode.error !== ""
						? ` — ${episode.error}`
						: ""}
				</Text>
			))}
		</Stack>
	);
}

export function SeriesImportCard() {
	const { t } = useTranslation();
	const [url, setUrl] = useState("");
	const [probe, setProbe] = useState<ImportProbe | null>(null);
	const [selected, setSelected] = useState<Set<string>>(new Set());
	const [error, setError] = useState<string | null>(null);
	const [jobID, setJobID] = useState<number | null>(null);
	const probeMutation = useImportProbe();
	const start = useStartImport();
	const cancel = useCancelImport();
	const jobs = useImportJobs();

	const seasons = useMemo(() => {
		const map = new Map<number, ImportProbe["episodes"]>();
		for (const episode of probe?.episodes ?? []) {
			const list = map.get(episode.season) ?? [];
			list.push(episode);
			map.set(episode.season, list);
		}
		return [...map.entries()].sort((a, b) => a[0] - b[0]);
	}, [probe]);

	const check = () => {
		setError(null);
		setProbe(null);
		setSelected(new Set());
		probeMutation.mutate(url.trim(), {
			onSuccess: (result) => {
				setProbe(result);
				setSelected(
					new Set(
						result.episodes.map((item) => keyOf(item.season, item.episode)),
					),
				);
			},
			onError: (err) =>
				setError(err instanceof Error ? err.message : t("import.probeError")),
		});
	};

	const toggle = (season: number, episode: number) => {
		setSelected((prev) => {
			const next = new Set(prev);
			const key = keyOf(season, episode);
			if (next.has(key)) next.delete(key);
			else next.add(key);
			return next;
		});
	};

	const startImport = () => {
		if (probe === null) return;
		const episodes = probe.episodes
			.filter((item) => selected.has(keyOf(item.season, item.episode)))
			.map((item) => ({ season: item.season, episode: item.episode }));
		if (episodes.length === 0) return;
		// Сезонный scope, если выбраны серии одного сезона: media-loader
		// не должен скачивать весь сериал ради одного сезона.
		// scope=season media-loader выводит из самой ссылки: для ссылки на
		// сериал он не сможет определить сезон и вернёт 502. Поэтому
		// season запрашиваем только когда probe уже разрешил сезон.
		const singleSeasonSource =
			probe.scope === "season" || (probe.seasons?.length ?? 1) <= 1;
		start.mutate(
			{
				url: url.trim(),
				scope: singleSeasonSource ? "season" : "series",
				title: probe.title,
				seriesID: probe.series_id,
				episodes,
			},
			{
				onSuccess: (job) => setJobID(job.id),
				onError: (err) =>
					setError(err instanceof Error ? err.message : t("import.startError")),
			},
		);
	};

	return (
		<Card withBorder padding="lg" radius="md">
			<Stack gap="sm">
				<Title order={2} size="h4">
					{t("import.title")}
				</Title>
				<Text size="sm" c="dimmed">
					{t("import.hint")}
				</Text>
				<Group align="end">
					<TextInput
						data-testid="import-url"
						label={t("import.url")}
						value={url}
						onChange={(event) => setUrl(event.currentTarget.value)}
						w={{ base: "100%", sm: 480 }}
					/>
					<Button loading={probeMutation.isPending} onClick={check}>
						{t("import.probe")}
					</Button>
				</Group>
				{error !== null && <Alert color="red">{error}</Alert>}
				{probe !== null && probe.kind === "episode" && (
					<Alert color="yellow">{t("import.singleVideo")}</Alert>
				)}
				{probe !== null && probe.kind === "series" && (
					<Stack gap="xs">
						<Text fw={600}>{probe.title}</Text>
						{seasons.map(([seasonNumber, episodes]) => (
							<Stack key={seasonNumber} gap={4}>
								<Group justify="space-between">
									<Text size="sm" fw={600}>
										{t("catalog.season", { number: seasonNumber })}
									</Text>
									<Button
										size="compact-xs"
										variant="subtle"
										onClick={() =>
											setSelected((prev) => {
												const next = new Set(prev);
												const allSelected = episodes.every((item) =>
													next.has(keyOf(item.season, item.episode)),
												);
												for (const item of episodes) {
													const key = keyOf(item.season, item.episode);
													if (allSelected) next.delete(key);
													else next.add(key);
												}
												return next;
											})
										}
									>
										{t("import.toggleSeason")}
									</Button>
								</Group>
								{episodes.map((item) => (
									<Checkbox
										key={keyOf(item.season, item.episode)}
										checked={selected.has(keyOf(item.season, item.episode))}
										onChange={() => toggle(item.season, item.episode)}
										label={`S${String(item.season).padStart(2, "0")}E${String(item.episode).padStart(2, "0")} · ${item.title || "—"}`}
									/>
								))}
							</Stack>
						))}
						<Group>
							<Button
								leftSection={<DownloadCloud size={16} />}
								loading={start.isPending}
								disabled={selected.size === 0}
								onClick={startImport}
							>
								{t("import.start", { count: selected.size })}
							</Button>
							<Text size="xs" c="dimmed">
								{t("import.limit")}
							</Text>
						</Group>
					</Stack>
				)}
				{jobID !== null && (
					<>
						<ImportProgress id={jobID} />
						<Button
							size="xs"
							variant="subtle"
							color="red"
							onClick={() => cancel.mutate(jobID)}
						>
							{t("import.cancel")}
						</Button>
					</>
				)}
				{(jobs.data ?? []).length > 0 && (
					<Stack gap={4}>
						<Text size="sm" fw={600}>
							{t("import.recent")}
						</Text>
						{(jobs.data ?? []).map((job) => (
							<Text key={job.id} size="xs" c="dimmed">
								{job.title || `#${job.id}`} · {t(`import.status.${job.status}`)}{" "}
								· {job.episodes_done}/{job.episodes_total}
							</Text>
						))}
					</Stack>
				)}
			</Stack>
		</Card>
	);
}

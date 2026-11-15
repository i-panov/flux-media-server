import {
	Alert,
	Button,
	Card,
	Group,
	Loader,
	Progress,
	Select,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useQueryClient } from "@tanstack/react-query";
import { Download, Link2, X } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	cancelMediaLoaderJob,
	type MediaLoaderJob,
	useMediaLoaderJobs,
	useStartMediaLoader,
} from "../../api/mediaLoader";
import type { UploadType } from "../../api/upload";

const VIDEO_FORMATS = [
	{ value: "mp4", label: "MP4" },
	{ value: "mkv", label: "MKV" },
];
const AUDIO_FORMATS = [
	{ value: "mp3", label: "MP3" },
	{ value: "m4a", label: "M4A" },
	{ value: "opus", label: "Opus" },
	{ value: "original", label: "Original" },
];
const QUALITIES = [
	"max",
	"2160p",
	"1440p",
	"1080p",
	"720p",
	"480p",
	"360p",
].map((value) => ({ value, label: value === "max" ? "Max" : value }));

const TERMINAL = new Set(["done", "error", "cancelled"]);

function JobCard({ job }: { job: MediaLoaderJob }) {
	const { t } = useTranslation();
	const queryClient = useQueryClient();
	const active = !TERMINAL.has(job.status);
	const cancel = () => {
		void cancelMediaLoaderJob(job.id).finally(() => {
			void queryClient.invalidateQueries({ queryKey: ["media-loader"] });
		});
	};
	return (
		<Card withBorder padding="sm" radius="sm" data-testid="upload-link-job">
			<Stack gap="xs">
				<Group justify="space-between">
					<Text size="sm" fw={500}>
						{job.title ?? job.filename ?? t("upload.link.job")}
					</Text>
					{active && (
						<Button
							variant="subtle"
							color="red"
							size="compact-sm"
							leftSection={<X size={14} />}
							onClick={cancel}
						>
							{t("upload.link.cancel")}
						</Button>
					)}
				</Group>
				{job.status === "importing" || job.status === "processing" ? (
					<Group gap="xs">
						<Loader size="xs" />
						<Text size="xs" c="dimmed">
							{t(`upload.link.status.${job.status}`)}
						</Text>
					</Group>
				) : (
					<Progress
						value={job.status === "done" ? 100 : (job.progress ?? 0)}
						animated={active}
					/>
				)}
				<Text size="xs" c="dimmed">
					{t(`upload.link.status.${job.status}`)}
					{job.stage !== undefined && job.stage !== "" ? ` · ${job.stage}` : ""}
				</Text>
				{job.error !== undefined && (
					<Alert color="red" variant="light">
						{job.error}
					</Alert>
				)}
			</Stack>
		</Card>
	);
}

export function LinkDownloadCard({ type }: { type: UploadType }) {
	const { t } = useTranslation();
	const [url, setUrl] = useState("");
	const [format, setFormat] = useState(type === "audio" ? "mp3" : "mp4");
	const [quality, setQuality] = useState("max");
	const start = useStartMediaLoader();
	const jobs = useMediaLoaderJobs();

	if (type === "image") {
		return null;
	}

	const submit = () => {
		const trimmed = url.trim();
		if (trimmed === "") return;
		start.mutate(
			{ url: trimmed, audioOnly: type === "audio", format, quality },
			{ onSuccess: () => setUrl("") },
		);
	};

	return (
		<Card withBorder padding="lg" radius="md" data-testid="upload-link-card">
			<Stack gap="sm">
				<Group gap="xs">
					<Link2 size={18} />
					<Title order={3} size="h4">
						{t("upload.link.title")}
					</Title>
				</Group>
				<Text size="sm" c="dimmed">
					{t("upload.link.hint")}
				</Text>
				<Group align="flex-end" wrap="wrap">
					<TextInput
						data-testid="upload-link-url"
						label={t("upload.link.url")}
						placeholder="https://..."
						value={url}
						onChange={(event) => setUrl(event.currentTarget.value)}
						disabled={start.isPending}
						w={{ base: "100%", sm: 360 }}
					/>
					<Select
						label={t("upload.link.format")}
						data={type === "audio" ? AUDIO_FORMATS : VIDEO_FORMATS}
						value={format}
						allowDeselect={false}
						onChange={(value) => setFormat(value ?? format)}
						w={120}
					/>
					{type === "video" && (
						<Select
							label={t("upload.link.quality")}
							data={QUALITIES}
							value={quality}
							allowDeselect={false}
							onChange={(value) => setQuality(value ?? quality)}
							w={120}
						/>
					)}
					<Button
						data-testid="upload-link-submit"
						leftSection={<Download size={16} />}
						loading={start.isPending}
						disabled={url.trim() === "" || start.isPending}
						onClick={submit}
					>
						{t("upload.link.submit")}
					</Button>
				</Group>

				{start.isError && (
					<Alert color="red" variant="light">
						{start.error instanceof Error
							? start.error.message
							: t("upload.link.failed")}
					</Alert>
				)}

				{jobs.isPending && (
					<Group gap="sm">
						<Loader size="sm" />
						<Text size="sm">{t("upload.link.starting")}</Text>
					</Group>
				)}
				{jobs.isError && (
					<Alert color="red" variant="light">
						{t("upload.link.failed")}
					</Alert>
				)}

				{(jobs.data ?? []).length > 0 && (
					<Stack gap="xs">
						<Text size="sm" fw={600}>
							{t("upload.link.queue")}
						</Text>
						{(jobs.data ?? []).map((job) => (
							<JobCard key={job.id} job={job} />
						))}
					</Stack>
				)}
			</Stack>
		</Card>
	);
}

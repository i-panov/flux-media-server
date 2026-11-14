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
import { Download, Link2, X } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	cancelMediaLoaderJob,
	useMediaLoaderJob,
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

export function LinkDownloadCard({ type }: { type: UploadType }) {
	const { t } = useTranslation();
	const [url, setUrl] = useState("");
	const [format, setFormat] = useState(type === "audio" ? "mp3" : "mp4");
	const [quality, setQuality] = useState("max");
	const [jobId, setJobId] = useState<string | null>(null);
	const start = useStartMediaLoader();
	const job = useMediaLoaderJob(jobId);
	const current = job.data;

	if (type === "image") {
		return null;
	}

	const submit = () => {
		const trimmed = url.trim();
		if (trimmed === "") return;
		start.mutate(
			{ url: trimmed, audioOnly: type === "audio", format, quality },
			{ onSuccess: (created) => setJobId(created.id) },
		);
	};

	const cancel = () => {
		if (jobId !== null) {
			void cancelMediaLoaderJob(jobId);
			setJobId(null);
		}
	};

	return (
		<Card withBorder padding="lg" radius="md">
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
						label={t("upload.link.url")}
						placeholder="https://..."
						value={url}
						onChange={(event) => setUrl(event.currentTarget.value)}
						disabled={
							start.isPending ||
							(jobId !== null &&
								current !== undefined &&
								!TERMINAL.has(current.status))
						}
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
						leftSection={<Download size={16} />}
						loading={start.isPending}
						disabled={
							url.trim() === "" ||
							(jobId !== null &&
								current !== undefined &&
								!TERMINAL.has(current.status))
						}
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

				{jobId !== null && current === undefined && (
					<Group gap="sm">
						<Loader size="sm" />
						<Text size="sm">{t("upload.link.starting")}</Text>
					</Group>
				)}

				{current !== undefined && (
					<Card withBorder padding="sm" radius="sm">
						<Stack gap="xs">
							<Group justify="space-between">
								<Text size="sm" fw={500}>
									{current.title ?? current.filename ?? t("upload.link.job")}
								</Text>
								{!TERMINAL.has(current.status) && (
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
							{current.status === "importing" ||
							current.status === "processing" ? (
								<Group gap="xs">
									<Loader size="xs" />
									<Text size="xs" c="dimmed">
										{t(`upload.link.status.${current.status}`)}
									</Text>
								</Group>
							) : (
								<Progress
									value={
										current.status === "done" ? 100 : (current.progress ?? 0)
									}
									animated={!TERMINAL.has(current.status)}
								/>
							)}
							<Text size="xs" c="dimmed">
								{t(`upload.link.status.${current.status}`, {
									stage: current.stage ?? "",
								})}
							</Text>
							{current.error !== undefined && (
								<Alert color="red" variant="light">
									{current.error}
								</Alert>
							)}
						</Stack>
					</Card>
				)}
			</Stack>
		</Card>
	);
}

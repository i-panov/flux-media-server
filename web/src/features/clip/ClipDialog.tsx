import {
	Alert,
	Button,
	Group,
	Modal,
	RangeSlider,
	Stack,
	Text,
	TextInput,
} from "@mantine/core";
import { Scissors } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { useClip, useCreateClip } from "../../api/clip";
import { formatDuration } from "../../core/format";
import type { Media } from "../../core/media";

export function ClipDialog({
	media,
	opened,
	onClose,
}: {
	media: Media;
	opened: boolean;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const mediaRef = useRef<HTMLVideoElement | HTMLAudioElement | null>(null);
	const create = useCreateClip();
	const [range, setRange] = useState<[number, number]>([0, 0]);
	const [title, setTitle] = useState("");
	const [taskID, setTaskID] = useState<number | null>(null);
	const [error, setError] = useState<string | null>(null);
	const task = useClip(taskID);
	const duration = Math.max(media.duration, 1);

	useEffect(() => {
		if (opened) {
			setRange([0, duration]);
			setTaskID(null);
			setError(null);
			setTitle("");
		}
	}, [opened, duration]);

	const onTimeUpdate = () => {
		const el = mediaRef.current;
		if (el === null) return;
		if (el.currentTime >= range[1]) {
			el.pause();
			el.currentTime = range[0];
		}
		if (el.currentTime < range[0]) {
			el.currentTime = range[0];
		}
	};

	const submit = () => {
		setError(null);
		create.mutate(
			{
				mediaID: media.id,
				start: range[0],
				end: range[1],
				title: title.trim() || undefined,
			},
			{
				onSuccess: (created) => setTaskID(created.id),
				onError: (err) =>
					setError(err instanceof Error ? err.message : t("clip.error")),
			},
		);
	};

	const status = task.data?.status;
	return (
		<Modal
			opened={opened}
			onClose={onClose}
			title={t("clip.title")}
			size="xl"
			centered
		>
			<Stack gap="sm">
				{media.type === "audio" ? (
					// biome-ignore lint/a11y/useMediaCaption: аудио без дорожек субтитров.
					<audio
						ref={(node) => {
							mediaRef.current = node;
						}}
						src={`/api/media/${media.id}/stream`}
						controls
						onTimeUpdate={onTimeUpdate}
						className="w-full"
					/>
				) : (
					// biome-ignore lint/a11y/useMediaCaption: субтитры для обрезки не нужны.
					<video
						ref={(node) => {
							mediaRef.current = node;
						}}
						src={`/api/media/${media.id}/stream`}
						poster={media.cover_url || media.thumbnail_url || undefined}
						controls
						onTimeUpdate={onTimeUpdate}
						className="aspect-video w-full rounded bg-black"
					/>
				)}
				<RangeSlider
					label={(value) => formatDuration(value)}
					min={0}
					max={duration}
					step={0.1}
					value={range}
					onChange={setRange}
					minRange={0.5}
				/>
				<Group justify="space-between">
					<Text size="sm">
						{formatDuration(range[0])} — {formatDuration(range[1])}
					</Text>
					<Text size="sm" c="dimmed">
						{formatDuration(range[1] - range[0])}
					</Text>
				</Group>
				<Group gap="xs">
					<Button
						size="xs"
						variant="light"
						onClick={() => {
							const el = mediaRef.current;
							if (el !== null) {
								setRange([
									el.currentTime,
									Math.max(el.currentTime + 1, range[1]),
								]);
							}
						}}
					>
						{t("clip.setStart")}
					</Button>
					<Button
						size="xs"
						variant="light"
						onClick={() => {
							const el = mediaRef.current;
							if (el !== null) {
								setRange([
									Math.min(range[0], el.currentTime - 1),
									el.currentTime,
								]);
							}
						}}
					>
						{t("clip.setEnd")}
					</Button>
					<Button
						size="xs"
						variant="subtle"
						onClick={() => {
							const el = mediaRef.current;
							if (el !== null) {
								el.currentTime = range[0];
								void el.play();
							}
						}}
					>
						{t("clip.preview")}
					</Button>
				</Group>
				<TextInput
					label={t("clip.name")}
					value={title}
					onChange={(event) => setTitle(event.currentTarget.value)}
					placeholder={`${media.title} — фрагмент`}
				/>
				{error !== null && <Alert color="red">{error}</Alert>}
				{status !== undefined && (
					<Alert
						color={
							status === "error" ? "red" : status === "done" ? "green" : "blue"
						}
					>
						{status === "done"
							? t("clip.done")
							: status === "error"
								? (task.data?.error ?? t("clip.error"))
								: t("clip.processing")}
					</Alert>
				)}
				<Group justify="flex-end">
					<Button variant="default" onClick={onClose}>
						{t("common.cancel")}
					</Button>
					<Button
						leftSection={<Scissors size={16} />}
						loading={create.isPending}
						disabled={
							range[1] - range[0] < 0.5 ||
							status === "queued" ||
							status === "processing"
						}
						onClick={submit}
					>
						{t("clip.submit")}
					</Button>
				</Group>
			</Stack>
		</Modal>
	);
}

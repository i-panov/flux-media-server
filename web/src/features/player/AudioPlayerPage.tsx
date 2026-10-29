import {
	ActionIcon,
	Alert,
	Button,
	Group,
	Skeleton,
	Slider,
	Stack,
	Tabs,
	Text,
	Textarea,
	Title,
	Tooltip,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Link, useNavigate } from "@tanstack/react-router";
import {
	ArrowLeft,
	Music,
	Pause,
	Play,
	SkipBack,
	SkipForward,
	Trash2,
} from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useLyrics, useSaveLyrics } from "../../api/lyrics";
import { useSession } from "../../api/session";
import { formatDuration } from "../../core/format";
import { useAudioPlayer } from "./AudioPlayerProvider";
import { CoverImage } from "./CoverImage";

function LyricsTab({ kind }: { kind: "lyrics" | "translation" }) {
	const { t } = useTranslation();
	const player = useAudioPlayer();
	const current = player.current;
	const lyrics = useLyrics(current?.id ?? 0, current !== null);
	const session = useSession();
	const save = useSaveLyrics(current?.id ?? 0);
	const [editing, setEditing] = useState(false);
	const [value, setValue] = useState("");

	if (current === null) {
		return null;
	}
	const text =
		kind === "lyrics"
			? (lyrics.data?.lyrics_text ?? "")
			: (lyrics.data?.translation ?? "");
	const isAdmin = session.data?.is_admin === true;

	const startEditing = () => {
		setValue(text);
		setEditing(true);
	};
	const submit = () => {
		save.mutate(
			{
				lyricsText:
					kind === "lyrics" ? value : (lyrics.data?.lyrics_text ?? ""),
				translation:
					kind === "translation" ? value : (lyrics.data?.translation ?? ""),
				syncData: lyrics.data?.sync_data ?? "",
				source: lyrics.data?.source ?? "user",
			},
			{
				onSuccess: () => setEditing(false),
				onError: (error) => {
					notifications.show({
						color: "red",
						title: t("player.saveError"),
						message: error instanceof ApiError ? error.message : "",
					});
				},
			},
		);
	};

	return (
		<Stack gap="md">
			<Group justify="space-between">
				<Text size="sm" c="dimmed">
					{kind === "lyrics" ? t("player.lyrics") : t("player.translation")}
				</Text>
				{isAdmin && lyrics.isSuccess && !editing && (
					<Button variant="light" size="xs" onClick={startEditing}>
						{text === "" ? t("player.addText") : t("player.edit")}
					</Button>
				)}
				{editing && (
					<Group gap="xs">
						<Button
							variant="default"
							size="xs"
							onClick={() => setEditing(false)}
						>
							{t("collections.cancel")}
						</Button>
						<Button size="xs" loading={save.isPending} onClick={submit}>
							{t("collections.save")}
						</Button>
					</Group>
				)}
			</Group>
			{lyrics.isPending ? (
				<Skeleton height={64} radius="sm" />
			) : lyrics.isError ? (
				<Alert color="red" variant="light" title={t("player.lyricsError")}>
					<Button
						variant="light"
						size="xs"
						mt="xs"
						onClick={() => void lyrics.refetch()}
					>
						{t("common.retry")}
					</Button>
				</Alert>
			) : editing ? (
				<Textarea
					value={value}
					onChange={(event) => setValue(event.currentTarget.value)}
					autosize
					minRows={12}
					maxRows={28}
				/>
			) : (
				<Text style={{ whiteSpace: "pre-wrap" }}>
					{text === "" ? t("player.noText") : text}
				</Text>
			)}
		</Stack>
	);
}

function QueueTab() {
	const { t } = useTranslation();
	const player = useAudioPlayer();
	if (player.queue.length === 0) {
		return <Text c="dimmed">{t("player.queueEmpty")}</Text>;
	}
	return (
		<Stack gap="xs">
			{player.queue.map((media, index) => (
				// biome-ignore lint/suspicious/noArrayIndexKey: один трек может стоять в очереди несколько раз.
				<Group key={`${media.id}-${index}`} gap="sm" wrap="nowrap">
					<Button
						variant={index === player.index ? "light" : "subtle"}
						justify="flex-start"
						className="min-w-0 flex-1"
						onClick={() => player.select(index)}
					>
						<Text truncate>
							{index === player.index ? "▶ " : ""}
							{media.title}
						</Text>
					</Button>
					<Tooltip label={t("player.removeFromQueue")} withArrow>
						<ActionIcon
							variant="subtle"
							color="red"
							aria-label={t("player.removeFromQueue")}
							onClick={() => player.removeAt(index)}
						>
							<Trash2 size={16} />
						</ActionIcon>
					</Tooltip>
				</Group>
			))}
		</Stack>
	);
}

export function AudioPlayerPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const player = useAudioPlayer();
	const current = player.current;
	// Пока тянем бегунок, показываем его позицию, а не время из элемента:
	// управляемый Slider без onChange не двигается под курсором.
	const [seekPreview, setSeekPreview] = useState<{
		mediaId: number;
		seconds: number;
	} | null>(null);
	const navigateBack = () => {
		void navigate({ to: "/audio" });
	};

	if (current === null) {
		return (
			<Stack gap="md" align="center" py="xl">
				<Music size={48} className="text-[var(--mantine-color-dimmed)]" />
				<Text c="dimmed">{t("player.nothingPlaying")}</Text>
				<Button component={Link} to="/audio" variant="light">
					{t("player.toAudio")}
				</Button>
			</Stack>
		);
	}

	const artists = current.artists.map((artist) => artist.name).join(", ");
	const maxDuration = Math.max(player.duration, 1);
	const position = Math.min(player.currentTime, maxDuration);
	const preview =
		seekPreview?.mediaId === current.id ? seekPreview.seconds : null;
	const sliderValue = preview ?? position;

	return (
		<Stack gap="lg" maw={960} mx="auto" w="100%">
			<Group justify="space-between">
				<Button
					variant="subtle"
					leftSection={<ArrowLeft size={16} />}
					onClick={navigateBack}
				>
					{t("player.toAudio")}
				</Button>
			</Group>

			{player.error !== null && (
				<Alert color="red" variant="light" title={t("player.error")}>
					{player.error}
				</Alert>
			)}

			<Group align="flex-start" gap="xl" wrap="wrap">
				<div className="grid h-60 w-60 shrink-0 place-items-center overflow-hidden rounded-lg bg-[var(--mantine-color-default-hover)]">
					<CoverImage src={current.cover_url} iconSize={48} />
				</div>
				<Stack
					gap="sm"
					className="min-w-0 flex-1 basis-full min-[48em]:basis-auto"
				>
					<Stack gap={2}>
						<Title order={1} size="h2" lineClamp={2}>
							{current.title}
						</Title>
						<Text c="dimmed">{artists === "" ? "—" : artists}</Text>
						{current.album !== "" && (
							<Text size="sm" c="dimmed">
								{current.album}
							</Text>
						)}
					</Stack>

					<Slider
						value={sliderValue}
						min={0}
						max={maxDuration}
						step={0.5}
						label={formatDuration(sliderValue)}
						onChange={(value) =>
							setSeekPreview({ mediaId: current.id, seconds: value })
						}
						onChangeEnd={(value) => {
							player.seek(value);
							setSeekPreview(null);
						}}
					/>
					<Group justify="space-between">
						<Text size="xs" c="dimmed">
							{formatDuration(sliderValue)}
						</Text>
						<Text size="xs" c="dimmed">
							{formatDuration(player.duration)}
						</Text>
					</Group>

					<Group justify="center" gap="md">
						<Tooltip label={t("player.previous")} withArrow>
							<ActionIcon
								variant="subtle"
								size="lg"
								aria-label={t("player.previous")}
								onClick={player.previous}
							>
								<SkipBack size={22} />
							</ActionIcon>
						</Tooltip>
						<ActionIcon
							variant="filled"
							radius="xl"
							size={56}
							aria-label={player.playing ? t("player.pause") : t("player.play")}
							onClick={player.toggle}
						>
							{player.playing ? (
								<Pause size={26} />
							) : (
								<Play size={26} fill="currentColor" />
							)}
						</ActionIcon>
						<Tooltip label={t("player.next")} withArrow>
							<ActionIcon
								variant="subtle"
								size="lg"
								aria-label={t("player.next")}
								onClick={player.next}
							>
								<SkipForward size={22} />
							</ActionIcon>
						</Tooltip>
					</Group>

					<Group gap="sm" wrap="nowrap">
						<Text size="xs" c="dimmed">
							{t("player.volume")}
						</Text>
						<Slider
							value={player.volume * 100}
							min={0}
							max={100}
							label={`${Math.round(player.volume * 100)}%`}
							onChange={(value) => player.setVolume(value / 100)}
							className="flex-1"
						/>
					</Group>
				</Stack>
			</Group>

			<Tabs defaultValue="lyrics">
				<Tabs.List>
					<Tabs.Tab value="lyrics">{t("player.lyrics")}</Tabs.Tab>
					<Tabs.Tab value="translation">{t("player.translation")}</Tabs.Tab>
					<Tabs.Tab value="queue">{t("player.queue")}</Tabs.Tab>
				</Tabs.List>
				<Tabs.Panel value="lyrics" pt="md">
					{/* key: при смене трека редактирование не должно переезжать
					на чужой текст — состояние сбрасывается пересозданием. */}
					<LyricsTab key={`lyrics-${current.id}`} kind="lyrics" />
				</Tabs.Panel>
				<Tabs.Panel value="translation" pt="md">
					<LyricsTab key={`translation-${current.id}`} kind="translation" />
				</Tabs.Panel>
				<Tabs.Panel value="queue" pt="md">
					<QueueTab />
				</Tabs.Panel>
			</Tabs>
		</Stack>
	);
}

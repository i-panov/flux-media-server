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
	Repeat,
	Repeat1,
	Shuffle,
	SkipBack,
	SkipForward,
	Trash2,
} from "lucide-react";
import { useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useLyrics, useSaveLyrics } from "../../api/lyrics";
import { useSession } from "../../api/session";
import { formatDuration } from "../../core/format";
import { clickNode, TVFocusScope, TVTab, useTVFocusable } from "../tv/tvFocus";
import { useAudioPlayer } from "./AudioPlayerProvider";
import { CoverImage } from "./CoverImage";
import { parseSyncedLyrics } from "./lyricsSync";
import { SyncedLyricsView } from "./SyncedLyricsView";
import { useTVPlayerRemote } from "./tvPlayerRemote";

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
	// LRC-синхронизация — только у лирики, как во Flutter.
	const syncLines =
		kind === "lyrics" && !editing
			? parseSyncedLyrics(lyrics.data?.sync_data ?? "")
			: [];
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
					aria-label={t("player.lyricsLabel")}
					autosize
					minRows={12}
					maxRows={28}
				/>
			) : syncLines.length > 0 ? (
				<SyncedLyricsView lines={syncLines} />
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
	const currentPrefix = t("player.currentPrefix");
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
							{index === player.index ? currentPrefix : ""}
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

function SeekSlider({
	mediaId,
	currentTime,
	duration,
	onSeek,
}: {
	mediaId: number;
	currentTime: number;
	duration: number;
	onSeek: (value: number) => void;
}) {
	// Пока тянем бегунок, показываем его позицию, а не время из элемента:
	// управляемый Slider без onChange не двигается под курсором.
	const [seekPreview, setSeekPreview] = useState<{
		mediaId: number;
		seconds: number;
	} | null>(null);
	// Трек начала драга: если посередине переключился трек (автопереход,
	// очередь), отпускание не должно сикать чужой трек на старую позицию.
	const dragMediaId = useRef<number | null>(null);
	const { t } = useTranslation();
	const maxDuration = Math.max(duration, 1);
	const position = Math.min(currentTime, maxDuration);
	const preview = seekPreview?.mediaId === mediaId ? seekPreview.seconds : null;
	const sliderValue = preview ?? position;
	return (
		<>
			<Slider
				value={sliderValue}
				min={0}
				max={maxDuration}
				step={0.5}
				label={formatDuration(sliderValue)}
				thumbLabel={t("player.seekLabel")}
				onChange={(value) => {
					if (dragMediaId.current === null) {
						dragMediaId.current = mediaId;
					}
					setSeekPreview({ mediaId, seconds: value });
				}}
				onChangeEnd={(value) => {
					const startedId = dragMediaId.current;
					dragMediaId.current = null;
					if (startedId !== null && startedId !== mediaId) {
						setSeekPreview(null);
						return;
					}
					onSeek(value);
					setSeekPreview(null);
				}}
			/>
			<Group justify="space-between">
				<Text size="xs" c="dimmed">
					{formatDuration(sliderValue)}
				</Text>
				<Text size="xs" c="dimmed">
					{formatDuration(duration)}
				</Text>
			</Group>
		</>
	);
}

// Кнопки транспорта с фокусом пульта: свой компонент, чтобы страница
// оставалась в лимите строк. В обычном режиме — обычные кнопки.
function TransportControls() {
	const { t } = useTranslation();
	const player = useAudioPlayer();
	const { targetRef: tvShuffleRef } = useTVFocusable<HTMLButtonElement>(
		"player-shuffle",
		clickNode,
		() => false,
	);
	const { targetRef: tvPrevRef } = useTVFocusable<HTMLButtonElement>(
		"player-prev",
		clickNode,
		() => false,
	);
	const { targetRef: tvPlayRef } = useTVFocusable<HTMLButtonElement>(
		"player-play",
		clickNode,
		() => false,
	);
	const { targetRef: tvNextRef } = useTVFocusable<HTMLButtonElement>(
		"player-next",
		clickNode,
		() => false,
	);
	const { targetRef: tvRepeatRef } = useTVFocusable<HTMLButtonElement>(
		"player-repeat",
		clickNode,
		() => false,
	);
	return (
		<Group justify="center" gap="md">
			<Tooltip label={t("player.shuffle")} withArrow>
				<ActionIcon
					variant={player.shuffle ? "filled" : "subtle"}
					size="lg"
					radius="xl"
					aria-label={t("player.shuffle")}
					aria-pressed={player.shuffle}
					ref={tvShuffleRef}
					onClick={player.toggleShuffle}
				>
					<Shuffle size={20} />
				</ActionIcon>
			</Tooltip>
			<Tooltip label={t("player.previous")} withArrow>
				<ActionIcon
					variant="subtle"
					size="lg"
					aria-label={t("player.previous")}
					data-testid="player-prev"
					ref={tvPrevRef}
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
				data-testid={player.playing ? "player-pause" : "player-play"}
				ref={tvPlayRef}
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
					data-testid="player-next"
					ref={tvNextRef}
					onClick={player.next}
				>
					<SkipForward size={22} />
				</ActionIcon>
			</Tooltip>
			<Tooltip
				label={
					player.repeat === "all"
						? t("player.repeatAll")
						: player.repeat === "one"
							? t("player.repeatOne")
							: t("player.repeatOff")
				}
				withArrow
			>
				<ActionIcon
					variant={player.repeat === "off" ? "subtle" : "filled"}
					size="lg"
					radius="xl"
					aria-label={
						player.repeat === "all"
							? t("player.repeatAll")
							: player.repeat === "one"
								? t("player.repeatOne")
								: t("player.repeatOff")
					}
					ref={tvRepeatRef}
					onClick={player.cycleRepeat}
				>
					{player.repeat === "one" ? (
						<Repeat1 size={20} />
					) : (
						<Repeat size={20} />
					)}
				</ActionIcon>
			</Tooltip>
		</Group>
	);
}

export function AudioPlayerPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const player = useAudioPlayer();
	const current = player.current;
	// Пульт в ТВ-режиме: стрелки сикают/меняют громкость, media-клавиши —
	// транспорт. Хук живёт на странице плеера, Back-клавиши остаются
	// за глобальным Back-хендлером.
	useTVPlayerRemote();
	// ТВ-режим: секция — точка входа spatial-навигации.
	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		"player-page",
		undefined,
		() => false,
	);
	const { targetRef: tvBackRef } = useTVFocusable<HTMLButtonElement>(
		"player-back",
		clickNode,
		() => false,
	);
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

	return (
		<Stack
			gap="lg"
			maw={960}
			mx="auto"
			w="100%"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-focus-key="player-page"
		>
			<TVFocusScope focusKey="player-page">
				<Group justify="space-between">
					<Button
						variant="subtle"
						leftSection={<ArrowLeft size={16} />}
						ref={tvBackRef}
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
							<Text c="dimmed">
								{artists === "" ? t("common.emptyFallback") : artists}
							</Text>
							{current.album !== "" && (
								<Text size="sm" c="dimmed">
									{current.album}
								</Text>
							)}
						</Stack>

						<SeekSlider
							mediaId={current.id}
							currentTime={player.currentTime}
							duration={player.duration}
							onSeek={(value) => player.seek(value)}
						/>

						<TransportControls />

						<Group gap="sm" wrap="nowrap">
							<Text size="xs" c="dimmed">
								{t("player.volume")}
							</Text>
							<Slider
								value={player.volume * 100}
								min={0}
								max={100}
								label={`${Math.round(player.volume * 100)}%`}
								thumbLabel={t("player.volumeLabel")}
								onChange={(value) => player.setVolume(value / 100)}
								className="flex-1"
							/>
						</Group>
					</Stack>
				</Group>

				<Tabs defaultValue="lyrics">
					<Tabs.List>
						<TVTab focusKey="player-tab-lyrics" value="lyrics">
							{t("player.lyrics")}
						</TVTab>
						<TVTab focusKey="player-tab-translation" value="translation">
							{t("player.translation")}
						</TVTab>
						<TVTab
							focusKey="player-tab-queue"
							value="queue"
							data-testid="player-queue-tab"
						>
							{t("player.queue")}
						</TVTab>
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
			</TVFocusScope>
		</Stack>
	);
}

import {
	ActionIcon,
	Button,
	Group,
	Menu,
	Modal,
	Stack,
	Text,
	Tooltip,
} from "@mantine/core";
import { MoreVertical, Music, Pencil, Trash2 } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useDeleteMedia, useMediaReload } from "../../api/media";
import { formatDuration } from "../../core/format";
import type { Media } from "../../core/media";
import { FavoriteButton } from "../favorites/FavoriteButton";
import { ChangeCoverButton } from "../media/ChangeCoverButton";
import { EditMetadataModal } from "../media/EditMetadataModal";
import { useAudioPlayer } from "../player/AudioPlayerProvider";
import { clickNode, useTVFocusable } from "../tv/tvFocus";
import { useTVMode } from "../tv/useTVMode";

// Строка трека: клик по всей строке запускает/ставит на паузу мини-плеер.
// Никакой детальной страницы у аудио нет: полный плеер открывается
// кликом по названию в мини-плеере.
export function AudioTrackRow({
	media,
	onPlay,
	showDelete = false,
	isCurrent = false,
}: {
	media: Media;
	onPlay?: () => void;
	showDelete?: boolean;
	isCurrent?: boolean;
}) {
	const { t } = useTranslation();
	const player = useAudioPlayer();
	const { capabilities } = useTVMode();
	const reload = useMediaReload(media.id);
	const remove = useDeleteMedia();
	const [deleteOpened, setDeleteOpened] = useState(false);
	const [editOpened, setEditOpened] = useState(false);
	const startPlayback = () => {
		if (onPlay !== undefined) {
			onPlay();
			return;
		}
		if (player.current?.id === media.id) {
			player.toggle();
			return;
		}
		player.playQueue([media], 0);
	};

	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`audio-row-${media.id}`,
		() => startPlayback(),
	);
	const { targetRef: menuRef } = useTVFocusable<HTMLButtonElement>(
		`audio-menu-${media.id}`,
		clickNode,
		undefined,
		{ secondary: true },
	);
	const hasCover = media.cover_url !== "" && !reload.failed;
	const artists = media.artists.map((artist) => artist.name).join(", ");

	const stop = (event: { stopPropagation: () => void }) => {
		event.stopPropagation();
	};

	return (
		<>
			<Group
				ref={tvRef}
				tabIndex={tvMode ? -1 : undefined}
				role="button"
				gap="sm"
				wrap="nowrap"
				onClick={startPlayback}
				onKeyDown={(event) => {
					if (event.key === "Enter" || event.key === " ") {
						event.preventDefault();
						startPlayback();
					}
				}}
				className={[
					"media-row cursor-pointer rounded-md border px-3 py-2",
					isCurrent
						? "border-[var(--mantine-color-violet-5)] bg-[var(--mantine-color-violet-light)]"
						: "border-[var(--mantine-color-default-border)]",
				].join(" ")}
			>
				<div className="grid h-12 w-12 shrink-0 place-items-center overflow-hidden rounded bg-[var(--mantine-color-default-hover)]">
					{hasCover ? (
						// biome-ignore lint/a11y/noNoninteractiveElementInteractions: onError здесь — ошибка загрузки, а не интеракция.
						<img
							key={reload.nonce}
							src={media.cover_url}
							alt=""
							loading="lazy"
							onError={reload.handleError}
							className="h-full w-full object-cover"
						/>
					) : (
						<Music
							size={20}
							aria-hidden="true"
							className="text-[var(--mantine-color-dimmed)]"
						/>
					)}
				</div>
				<Stack gap={0} className="min-w-0 flex-1">
					<Text
						fw={600}
						size="sm"
						truncate
						c={isCurrent ? "violet" : undefined}
					>
						{media.title}
					</Text>
					<Text size="xs" c="dimmed" truncate>
						{artists === "" ? t("common.emptyFallback") : artists}
					</Text>
				</Stack>
				{media.duration > 0 && (
					<Text size="xs" c="dimmed" className="shrink-0">
						{formatDuration(media.duration)}
					</Text>
				)}
				<Group gap={2} wrap="nowrap" className="shrink-0" onClick={stop}>
					<FavoriteButton mediaId={media.id} type="audio" />
					<Menu position="bottom-end" withinPortal>
						<Menu.Target>
							<Tooltip label={t("common.more")} withArrow>
								<ActionIcon
									ref={menuRef}
									variant="subtle"
									aria-label={t("common.more")}
								>
									<MoreVertical size={18} />
								</ActionIcon>
							</Tooltip>
						</Menu.Target>
						<Menu.Dropdown>
							{capabilities.canEditMetadata && (
								<Menu.Item
									leftSection={<Pencil size={16} />}
									onClick={() => setEditOpened(true)}
								>
									{t("metadata.edit")}
								</Menu.Item>
							)}
							{capabilities.canChangeCover && (
								<ChangeCoverButton mediaId={media.id} asMenuItem />
							)}
							{showDelete && capabilities.canDelete && (
								<Menu.Item
									color="red"
									leftSection={<Trash2 size={16} />}
									onClick={() => setDeleteOpened(true)}
								>
									{t("trash.deleteAction")}
								</Menu.Item>
							)}
						</Menu.Dropdown>
					</Menu>
				</Group>
			</Group>
			<Modal
				opened={deleteOpened}
				onClose={() => setDeleteOpened(false)}
				title={t("trash.deleteTitle")}
				centered
			>
				<Stack gap="md">
					<Text size="sm">{t("trash.deleteConfirm")}</Text>
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setDeleteOpened(false)}>
							{t("common.cancel")}
						</Button>
						<Button
							color="red"
							loading={remove.isPending}
							onClick={() => {
								remove.mutate(media.id, {
									onSuccess: () => setDeleteOpened(false),
								});
							}}
						>
							{t("trash.deleteAction")}
						</Button>
					</Group>
				</Stack>
			</Modal>
			{editOpened && (
				<EditMetadataModal
					key={media.id}
					opened
					media={media}
					onClose={() => setEditOpened(false)}
				/>
			)}
		</>
	);
}

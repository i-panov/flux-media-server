import { ActionIcon, Group, Stack, Text, Tooltip } from "@mantine/core";
import { setFocus } from "@noriginmedia/norigin-spatial-navigation";
import { Link } from "@tanstack/react-router";
import { Music, Pause, Play, RotateCw } from "lucide-react";
import { useId } from "react";
import { useTranslation } from "react-i18next";
import { useMediaReload } from "../../api/media";
import { formatDuration } from "../../core/format";
import type { Media } from "../../core/media";
import { FavoriteButton } from "../favorites/FavoriteButton";
import { DeleteMediaButton } from "../media/DeleteMediaButton";
import { clickFirstLink, clickNode, useTVFocusable } from "../tv/tvFocus";

// Плоская строка трека для раздела аудио (как во Flutter): обложка,
// название, исполнители, длительность и действия в один ряд —
// никаких карточек с лесенкой кнопок.
export function AudioTrackRow({
	media,
	onPlay,
	showDelete,
	isCurrent = false,
	isPlaying = false,
}: {
	media: Media;
	onPlay?: () => void;
	showDelete?: boolean;
	isCurrent?: boolean;
	isPlaying?: boolean;
}) {
	const { t } = useTranslation();
	const reload = useMediaReload(media.id);
	// ТВ-режим: строка — spatial-цель, Enter открывает детали через ссылку.
	// Кнопка play внутри остаётся нативной (Tab/мышь).
	// Суффикс useId: тот же трек бывает сразу в списке и избранном.
	const instanceKey = useId().replaceAll(":", "");
	const rowFocusKey = `audio-row-${media.id}-${instanceKey}`;
	const playFocusKey = `audio-play-${media.id}-${instanceKey}`;
	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		rowFocusKey,
		clickFirstLink,
		(direction) => {
			// Play лежит поверх широкой строки; обычная геометрия не видит
			// его справа, поэтому уводим фокус явно.
			if (direction === "right") {
				void setFocus(playFocusKey);
				return false;
			}
			return true;
		},
	);
	const { targetRef: playRef } = useTVFocusable<HTMLButtonElement>(
		playFocusKey,
		clickNode,
		undefined,
		{ secondary: true },
	);
	// Обложки может не быть (mp3 без тегов): сразу плейсхолдер, без <img src="">.
	const hasCover = media.cover_url !== "" && !reload.failed;
	const artists = media.artists.map((artist) => artist.name).join(", ");
	return (
		<Group
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			gap="sm"
			wrap="nowrap"
			className={[
				"media-row rounded-md border px-3 py-2",
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
				<Link
					to="/audio/$id"
					params={{ id: String(media.id) }}
					className="no-underline [color:inherit]"
				>
					<Text fw={600} size="sm" truncate>
						{media.title}
					</Text>
				</Link>
				<Text size="xs" c="dimmed" truncate>
					{artists === "" ? t("common.emptyFallback") : artists}
				</Text>
			</Stack>
			{media.duration > 0 && (
				<Text size="xs" c="dimmed" className="shrink-0">
					{formatDuration(media.duration)}
				</Text>
			)}
			<Group gap={4} wrap="nowrap" className="shrink-0">
				{onPlay !== undefined && (
					<Tooltip
						label={
							isCurrent && isPlaying ? t("player.pause") : t("player.play")
						}
						withArrow
					>
						<ActionIcon
							ref={playRef}
							variant="filled"
							radius="xl"
							size="lg"
							aria-label={
								isCurrent && isPlaying ? t("player.pause") : t("player.play")
							}
							onClick={onPlay}
						>
							{isCurrent && isPlaying ? (
								<Pause size={18} />
							) : (
								<Play size={18} fill="currentColor" />
							)}
						</ActionIcon>
					</Tooltip>
				)}
				<FavoriteButton mediaId={media.id} type="audio" />
				{showDelete === true && (
					<DeleteMediaButton mediaId={media.id} iconOnly />
				)}
				{reload.failed && (
					<Tooltip label={t("common.retry")} withArrow>
						<ActionIcon
							variant="subtle"
							aria-label={t("common.retry")}
							onClick={reload.retry}
						>
							<RotateCw size={18} />
						</ActionIcon>
					</Tooltip>
				)}
			</Group>
		</Group>
	);
}

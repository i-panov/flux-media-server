import { Card, Text } from "@mantine/core";
import { Music } from "lucide-react";
import { useId } from "react";
import { useTranslation } from "react-i18next";
import { useMediaReload } from "../../api/media";
import { formatDuration } from "../../core/format";
import type { Media } from "../../core/media";
import { FavoriteButton } from "../favorites/FavoriteButton";
import { useAudioPlayer } from "../player/AudioPlayerProvider";
import { clickFirstLink, useTVFocusable } from "../tv/tvFocus";

export function AudioCard({ media }: { media: Media }) {
	const { t } = useTranslation();
	const player = useAudioPlayer();
	const reload = useMediaReload(media.id);
	// ТВ-режим: карточка — spatial-цель, Enter повторяет клик по ссылке.
	// Суффикс useId: то же медиа бывает сразу в сетке и избранном.
	const instanceKey = useId().replaceAll(":", "");
	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`audio-card-${media.id}-${instanceKey}`,
		clickFirstLink,
	);
	// Обложки может не быть (mp3 без тегов): сразу плейсхолдер, без <img src="">.
	const hasCover = media.cover_url !== "" && !reload.failed;
	const artists = media.artists.map((artist) => artist.name).join(", ");
	return (
		<div
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			className="media-card relative"
		>
			<button
				type="button"
				onClick={() => player.playQueue([media], 0)}
				className="block w-full cursor-pointer border-0 bg-transparent p-0 text-left [color:inherit]"
			>
				<Card withBorder padding="sm" radius="md">
					<Card.Section className="relative">
						{hasCover ? (
							// Картинка в абсолюте: иначе её intrinsic-размер
							// растягивает aspect-бокс (как было в сетке мемов).
							// biome-ignore lint/a11y/noNoninteractiveElementInteractions: onError здесь — ошибка загрузки, а не интеракция.
							<img
								key={reload.nonce}
								src={media.cover_url}
								alt=""
								loading="lazy"
								onError={reload.handleError}
								className="absolute inset-0 h-full w-full object-cover"
							/>
						) : (
							<div
								aria-hidden="true"
								className="grid aspect-square w-full place-items-center bg-[var(--mantine-color-default-hover)]"
							>
								<Music
									size={32}
									className="text-[var(--mantine-color-dimmed)]"
								/>
							</div>
						)}
						{media.duration > 0 && (
							<Text
								size="xs"
								fw={600}
								className="absolute right-2 bottom-2 rounded bg-black/70 px-1.5 py-0.5 text-white"
							>
								{formatDuration(media.duration)}
							</Text>
						)}
					</Card.Section>
					<Text fw={600} size="sm" mt="xs" lineClamp={2}>
						{media.title}
					</Text>
					<Text size="xs" c="dimmed" lineClamp={1}>
						{artists === "" ? t("common.emptyFallback") : artists}
					</Text>
				</Card>
			</button>
			<FavoriteButton
				mediaId={media.id}
				type="audio"
				className="absolute top-2 left-2 z-10"
			/>
		</div>
	);
}

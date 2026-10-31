import { ActionIcon, Card } from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { Image as ImageIcon, RotateCw } from "lucide-react";
import { useId } from "react";
import { useTranslation } from "react-i18next";
import { useMediaReload } from "../../api/media";
import type { Media } from "../../core/media";
import { FavoriteButton } from "../favorites/FavoriteButton";
import { clickFirstLink, useTVFocusable } from "../tv/tvFocus";

// Квадратная плитка галереи: подписи нет, название уходит в aria-label
// ссылки. Превью — серверный JPEG до 512 px, оригинал грузится только
// в просмотрщике.
export function MemeCard({ media }: { media: Media }) {
	const { t } = useTranslation();
	const reload = useMediaReload(media.id);
	// ТВ-режим: плитка — spatial-цель, Enter повторяет клик по ссылке.
	// Суффикс useId: то же медиа бывает сразу в сетке и избранном.
	const instanceKey = useId().replaceAll(":", "");
	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`meme-card-${media.id}-${instanceKey}`,
		clickFirstLink,
	);
	const src =
		media.thumbnail_url === ""
			? `/api/media/${media.id}/stream`
			: media.thumbnail_url;
	return (
		<div ref={tvRef} tabIndex={tvMode ? -1 : undefined} className="relative">
			<Link
				to="/memes/$id"
				params={{ id: String(media.id) }}
				aria-label={media.title}
				className="block"
			>
				<Card withBorder padding={0} radius="md" className="overflow-hidden">
					<div className="relative aspect-square bg-[var(--mantine-color-default-hover)]">
						{reload.failed ? (
							<div
								aria-hidden="true"
								className="grid h-full w-full place-items-center"
							>
								<ImageIcon
									size={28}
									className="text-[var(--mantine-color-dimmed)]"
								/>
							</div>
						) : (
							// Картинка в абсолюте: иначе её intrinsic-размер
							// (портрет/панорама) растягивает aspect-бокс и
							// скачет вся сетка — проверено на живых мемах.
							// biome-ignore lint/a11y/noNoninteractiveElementInteractions: onError здесь — ошибка загрузки, а не интеракция.
							<img
								key={reload.nonce}
								src={src}
								alt=""
								loading="lazy"
								decoding="async"
								onError={reload.handleError}
								className="absolute inset-0 h-full w-full object-cover"
							/>
						)}
					</div>
				</Card>
			</Link>
			<FavoriteButton
				mediaId={media.id}
				type="image"
				className="absolute top-2 left-2 z-10"
			/>
			{reload.failed && (
				<ActionIcon
					variant="filled"
					size="lg"
					radius="xl"
					aria-label={t("common.retry")}
					className="absolute top-2 right-2"
					onClick={reload.retry}
				>
					<RotateCw size={18} />
				</ActionIcon>
			)}
		</div>
	);
}

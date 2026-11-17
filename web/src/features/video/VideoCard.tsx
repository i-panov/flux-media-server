import { Card, Text } from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { Check, Film } from "lucide-react";
import { useId } from "react";
import { useMediaReload } from "../../api/media";
import { formatDuration } from "../../core/format";
import type { Media } from "../../core/media";
import { FavoriteButton } from "../favorites/FavoriteButton";
import { clickFirstLink, useTVFocusable } from "../tv/tvFocus";

function ThumbImage({
	src,
	alt,
	nonce,
	onError,
}: {
	src: string;
	alt: string;
	nonce: number;
	onError: () => void;
}) {
	return (
		// biome-ignore lint/a11y/noNoninteractiveElementInteractions: onError здесь — ошибка загрузки, а не интеракция.
		<img
			key={nonce}
			src={src}
			alt={alt}
			loading="lazy"
			onError={onError}
			className="aspect-video w-full object-cover"
		/>
	);
}

export function VideoCard({
	media,
	selectable = false,
	selected = false,
	onToggleSelect,
}: {
	media: Media;
	selectable?: boolean;
	selected?: boolean;
	onToggleSelect?: (mediaId: number) => void;
}) {
	const reload = useMediaReload(media.id);
	// ТВ-режим: карточка — spatial-цель, Enter повторяет клик по ссылке.
	// В обычном режиме focusable=false, поведение не меняется.
	// Суффикс useId: то же медиа бывает сразу в сетке, избранном
	// и продолжении — ключи обязаны быть уникальны на странице.
	const instanceKey = useId().replace(/:/g, "");
	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`video-card-${media.id}-${instanceKey}`,
		clickFirstLink,
	);
	// Пустой URL (превью ещё не сгенерировано) и окончательно битая
	// картинка: вместо <img src=""> — плейсхолдер без лишних запросов.
	const imageURL = media.cover_url || media.thumbnail_url;
	const hasThumb = imageURL !== "" && !reload.failed;
	if (selectable) {
		return (
			<button
				type="button"
				onClick={() => onToggleSelect?.(media.id)}
				aria-pressed={selected}
				className={[
					"media-card relative flex h-full flex-col rounded-md border-2 p-0 text-left",
					selected
						? "border-[var(--mantine-color-violet-5)]"
						: "border-transparent",
				].join(" ")}
			>
				<Card withBorder padding="sm" radius="md" h="100%">
					<Card.Section className="relative">
						{hasThumb ? (
							<ThumbImage
								src={imageURL}
								alt={media.title}
								nonce={reload.nonce}
								onError={reload.handleError}
							/>
						) : (
							<div className="grid aspect-video w-full place-items-center bg-[var(--mantine-color-default-hover)]">
								<Film
									size={32}
									className="text-[var(--mantine-color-dimmed)]"
								/>
							</div>
						)}
						{selected && (
							<span className="absolute inset-0 grid place-items-center bg-black/40">
								<Check size={28} className="text-white" />
							</span>
						)}
					</Card.Section>
					<Text fw={600} size="sm" mt="xs" lineClamp={2}>
						{media.title}
					</Text>
				</Card>
			</button>
		);
	}
	return (
		<div
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			className="media-card relative flex h-full flex-col"
		>
			<Link
				to="/video/$id"
				params={{ id: String(media.id) }}
				className="flex-1 no-underline [color:inherit]"
			>
				<Card withBorder padding="sm" radius="md" h="100%">
					<Card.Section className="relative">
						{hasThumb ? (
							<ThumbImage
								src={imageURL}
								alt={media.title}
								nonce={reload.nonce}
								onError={reload.handleError}
							/>
						) : (
							<div
								aria-hidden="true"
								className="grid aspect-video w-full place-items-center bg-[var(--mantine-color-default-hover)]"
							>
								<Film
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
					<Text
						fw={600}
						size="sm"
						mt="xs"
						lineClamp={2}
						className="min-h-[2.4rem]"
					>
						{media.title}
					</Text>
					{media.year > 0 && (
						<Text size="xs" c="dimmed">
							{media.year}
						</Text>
					)}
				</Card>
			</Link>
			<FavoriteButton
				mediaId={media.id}
				type="video"
				className="absolute top-2 left-2 z-10"
			/>
		</div>
	);
}

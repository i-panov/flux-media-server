import { ActionIcon, Checkbox, Tooltip } from "@mantine/core";
import { FolderInput, X } from "lucide-react";
import { useTranslation } from "react-i18next";
import type { Media, MediaType } from "../../core/media";
import { AudioCard } from "../audio/AudioCard";
import { MemeCard } from "../memes/MemeCard";
import { useTVFocusable } from "../tv/tvFocus";
import { VideoCard } from "../video/VideoCard";

export function CollectionCard({
	media,
	type,
	onRemove,
	onMove,
	selected = false,
	onToggle,
}: {
	media: Media;
	type: MediaType;
	onRemove: () => void;
	onMove: () => void;
	selected?: boolean;
	onToggle?: () => void;
}) {
	const { t } = useTranslation();
	const { targetRef: selectRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`collection-select-${media.id}`,
		() => onToggle?.(),
	);
	return (
		<div className="relative">
			{onToggle !== undefined && (
				<div
					ref={selectRef}
					tabIndex={tvMode ? -1 : undefined}
					className="absolute top-2 right-2 z-20 rounded bg-[var(--mantine-color-body)] p-1"
				>
					<Checkbox
						checked={selected}
						onChange={onToggle}
						aria-label={media.title}
					/>
				</div>
			)}
			{type === "video" ? (
				<VideoCard media={media} />
			) : type === "audio" ? (
				<AudioCard media={media} />
			) : (
				<MemeCard media={media} />
			)}
			<Tooltip label={t("collections.removeItem")} withArrow>
				<ActionIcon
					variant="filled"
					color="red"
					size="lg"
					radius="xl"
					aria-label={t("collections.removeItem")}
					className="absolute bottom-2 left-2 z-10"
					onClick={onRemove}
				>
					<X size={18} />
				</ActionIcon>
			</Tooltip>
			<Tooltip label={t("collections.moveItem")} withArrow>
				<ActionIcon
					variant="filled"
					size="lg"
					radius="xl"
					aria-label={t("collections.moveItem")}
					className="absolute bottom-2 right-2 z-10"
					onClick={onMove}
				>
					<FolderInput size={18} />
				</ActionIcon>
			</Tooltip>
		</div>
	);
}

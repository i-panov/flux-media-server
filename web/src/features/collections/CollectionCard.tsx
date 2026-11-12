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
	readOnly = false,
}: {
	media: Media;
	type: MediaType;
	onRemove: () => void;
	onMove: () => void;
	selected?: boolean;
	onToggle?: () => void;
	readOnly?: boolean;
}) {
	const { t } = useTranslation();
	const { targetRef: selectRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`collection-select-${media.id}`,
		() => onToggle?.(),
	);
	return (
		<div className="relative flex h-full flex-col">
			{!readOnly && onToggle !== undefined && (
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
			{!readOnly && (
				<div className="-mt-px flex items-center justify-end gap-1 rounded-b-md border border-t-0 border-[var(--mantine-color-default-border)] bg-[var(--mantine-color-body)] px-2 py-1">
					<Tooltip label={t("collections.removeItem")} withArrow>
						<ActionIcon
							variant="light"
							color="red"
							size="md"
							radius="md"
							aria-label={t("collections.removeItem")}
							onClick={onRemove}
						>
							<X size={16} />
						</ActionIcon>
					</Tooltip>
					<Tooltip label={t("collections.moveItem")} withArrow>
						<ActionIcon
							variant="light"
							color="violet"
							size="md"
							radius="md"
							aria-label={t("collections.moveItem")}
							onClick={onMove}
						>
							<FolderInput size={16} />
						</ActionIcon>
					</Tooltip>
				</div>
			)}
		</div>
	);
}

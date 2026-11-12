import { ActionIcon, Checkbox, Menu, Tooltip } from "@mantine/core";
import { FolderInput, MoreVertical, X } from "lucide-react";
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
				<Menu position="bottom-end" withinPortal>
					<Menu.Target>
						<Tooltip label={t("common.more")} withArrow>
							<ActionIcon
								variant="filled"
								color="dark"
								size="sm"
								radius="md"
								aria-label={t("common.more")}
								className="absolute top-2 right-10 z-20"
							>
								<MoreVertical size={14} />
							</ActionIcon>
						</Tooltip>
					</Menu.Target>
					<Menu.Dropdown>
						<Menu.Item
							color="red"
							leftSection={<X size={14} />}
							onClick={onRemove}
						>
							{t("collections.removeItem")}
						</Menu.Item>
						<Menu.Item leftSection={<FolderInput size={14} />} onClick={onMove}>
							{t("collections.moveItem")}
						</Menu.Item>
					</Menu.Dropdown>
				</Menu>
			)}
		</div>
	);
}

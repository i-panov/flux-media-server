import { ActionIcon, Tooltip } from "@mantine/core";
import { FolderInput, X } from "lucide-react";
import { useTranslation } from "react-i18next";
import type { Media, MediaType } from "../../core/media";
import { AudioCard } from "../audio/AudioCard";
import { MemeCard } from "../memes/MemeCard";
import { VideoCard } from "../video/VideoCard";

export function CollectionCard({
	media,
	type,
	onRemove,
	onMove,
}: {
	media: Media;
	type: MediaType;
	onRemove: () => void;
	onMove: () => void;
}) {
	const { t } = useTranslation();
	return (
		<div className="relative">
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

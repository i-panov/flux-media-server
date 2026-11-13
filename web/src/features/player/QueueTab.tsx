import { Group, Stack, Text, Tooltip } from "@mantine/core";
import { ArrowDown, ArrowUp, Trash2 } from "lucide-react";
import { useTranslation } from "react-i18next";
import { TVActionIcon, TVButton } from "../tv/tvFocus";
import { useAudioPlayer } from "./AudioPlayerProvider";

export function QueueTab() {
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
					<TVButton
						focusKey={`queue-track-${index}`}
						variant={index === player.index ? "light" : "subtle"}
						justify="flex-start"
						className="min-w-0 flex-1"
						onClick={() => player.select(index)}
					>
						<Text truncate>
							{index === player.index ? currentPrefix : ""}
							{media.title}
						</Text>
					</TVButton>
					<TVActionIcon
						focusKey={`queue-up-${index}`}
						variant="subtle"
						aria-label={t("player.moveUp")}
						disabled={index === 0}
						onClick={() => player.move(index, index - 1)}
					>
						<ArrowUp size={16} />
					</TVActionIcon>
					<TVActionIcon
						focusKey={`queue-down-${index}`}
						variant="subtle"
						aria-label={t("player.moveDown")}
						disabled={index === player.queue.length - 1}
						onClick={() => player.move(index, index + 1)}
					>
						<ArrowDown size={16} />
					</TVActionIcon>
					<Tooltip label={t("player.removeFromQueue")} withArrow>
						<TVActionIcon
							focusKey={`queue-remove-${index}`}
							variant="subtle"
							color="red"
							aria-label={t("player.removeFromQueue")}
							onClick={() => player.removeAt(index)}
						>
							<Trash2 size={16} />
						</TVActionIcon>
					</Tooltip>
				</Group>
			))}
		</Stack>
	);
}

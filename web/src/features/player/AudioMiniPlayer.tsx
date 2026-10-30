import {
	ActionIcon,
	Group,
	Progress,
	Stack,
	Text,
	Tooltip,
} from "@mantine/core";
import { Link } from "@tanstack/react-router";
import {
	Pause,
	Play,
	SkipBack,
	SkipForward,
	TriangleAlert,
	X,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { formatDuration } from "../../core/format";
import { useAudioPlayer } from "./AudioPlayerProvider";
import { CoverImage } from "./CoverImage";
import { useMiniPlayerVisible } from "./useMiniPlayerVisible";

export function AudioMiniPlayer() {
	const { t } = useTranslation();
	const player = useAudioPlayer();
	const visible = useMiniPlayerVisible();
	const current = player.current;
	if (!visible || current === null) {
		return null;
	}
	const artists = current.artists.map((artist) => artist.name).join(", ");
	const progress =
		player.duration > 0 ? (player.currentTime / player.duration) * 100 : 0;
	return (
		<div className="audio-mini-player border-t border-[var(--mantine-color-default-border)] bg-[var(--mantine-color-body)]">
			<Progress value={Math.min(progress, 100)} size={2} radius={0} />
			<Group gap="sm" wrap="nowrap" px="md" py={6}>
				<Link
					to="/player"
					className="flex min-w-0 flex-1 items-center gap-3 no-underline [color:inherit]"
				>
					<div className="grid h-10 w-10 shrink-0 place-items-center overflow-hidden rounded bg-[var(--mantine-color-default-hover)]">
						<CoverImage src={current.cover_url} iconSize={18} />
					</div>
					<Stack gap={0} className="min-w-0">
						<Group gap={4} wrap="nowrap" className="min-w-0">
							<Text size="sm" fw={600} truncate>
								{current.title}
							</Text>
							{player.error !== null && (
								<Tooltip label={player.error} withArrow>
									<TriangleAlert
										size={16}
										className="shrink-0 text-[var(--mantine-color-red-6)]"
									/>
								</Tooltip>
							)}
						</Group>
						<Text size="xs" c="dimmed" truncate>
							{artists === "" ? t("common.emptyFallback") : artists}
						</Text>
					</Stack>
				</Link>
				<Text size="xs" c="dimmed" visibleFrom="sm">
					{formatDuration(player.currentTime)} /{" "}
					{formatDuration(player.duration)}
				</Text>
				<Group gap={4} wrap="nowrap">
					<Tooltip label={t("player.previous")} withArrow>
						<ActionIcon
							variant="subtle"
							aria-label={t("player.previous")}
							data-testid="player-prev"
							onClick={player.previous}
						>
							<SkipBack size={18} />
						</ActionIcon>
					</Tooltip>
					<Tooltip
						label={player.playing ? t("player.pause") : t("player.play")}
						withArrow
					>
						<ActionIcon
							variant="filled"
							radius="xl"
							size="lg"
							aria-label={player.playing ? t("player.pause") : t("player.play")}
							data-testid={player.playing ? "player-pause" : "player-play"}
							onClick={player.toggle}
						>
							{player.playing ? (
								<Pause size={18} />
							) : (
								<Play size={18} fill="currentColor" />
							)}
						</ActionIcon>
					</Tooltip>
					<Tooltip label={t("player.next")} withArrow>
						<ActionIcon
							variant="subtle"
							aria-label={t("player.next")}
							data-testid="player-next"
							onClick={player.next}
						>
							<SkipForward size={18} />
						</ActionIcon>
					</Tooltip>
					<Tooltip label={t("player.close")} withArrow>
						<ActionIcon
							variant="subtle"
							aria-label={t("player.close")}
							onClick={player.clear}
						>
							<X size={18} />
						</ActionIcon>
					</Tooltip>
				</Group>
			</Group>
		</div>
	);
}

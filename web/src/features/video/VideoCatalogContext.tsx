import { Anchor, Button, Group, Stack, Text } from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import {
	useMediaCatalogContext,
	useRemoveEpisode,
	useRemoveFilm,
} from "../../api/catalog";
import { useSession } from "../../api/session";
import { useTVMode } from "../tv/useTVMode";

export function VideoCatalogContext({ mediaId }: { mediaId: number }) {
	const { t } = useTranslation();
	const context = useMediaCatalogContext(mediaId);
	const session = useSession();
	const { capabilities } = useTVMode();
	const removeEpisode = useRemoveEpisode();
	const removeFilm = useRemoveFilm();
	if (context.data === undefined) {
		return null;
	}
	const { work_id, work_title, work_kind, season_number, episode_number } =
		context.data;
	const hasWork = work_id !== undefined;
	return (
		<Stack gap={4}>
			{hasWork && (
				<Group gap="xs">
					<Text size="sm" c="dimmed">
						{work_kind === "film_series"
							? t("catalog.filmSeries")
							: t("catalog.seriesOne")}
						:
					</Text>
					<Anchor component={Link} to={`/series/${work_id}`}>
						{work_title || `#${work_id}`}
					</Anchor>
					{work_kind === "series" && (
						<Text size="sm" c="dimmed">
							· {t("catalog.season", { number: season_number })}
							{episode_number == null
								? ""
								: ` · ${t("catalog.episode", { number: episode_number })}`}
						</Text>
					)}
				</Group>
			)}
			{session.data?.is_admin === true &&
				capabilities.canAccessAdmin &&
				hasWork && (
					<Button
						size="compact-xs"
						color="red"
						variant="subtle"
						w="fit-content"
						loading={removeEpisode.isPending || removeFilm.isPending}
						onClick={() => {
							const detail = context.data;
							if (detail.work_id === undefined) return;
							if (!window.confirm(t("catalog.removeFromCatalogConfirm")))
								return;
							const action =
								detail.season_id === undefined
									? removeFilm.mutateAsync({
											workID: detail.work_id,
											mediaID: mediaId,
										})
									: removeEpisode.mutateAsync({
											seasonID: detail.season_id,
											mediaID: mediaId,
										});
							void action.catch(() =>
								notifications.show({
									message: t("catalog.removeError"),
									color: "red",
								}),
							);
						}}
					>
						{t("catalog.removeFromCatalog")}
					</Button>
				)}
			{context.data.franchises.map((franchise) => (
				<Group key={franchise.id} gap="xs">
					<Text size="sm" c="dimmed">
						{t("catalog.franchise")}:
					</Text>
					<Anchor component={Link} to={`/franchises/${franchise.id}`}>
						{franchise.name}
					</Anchor>
				</Group>
			))}
		</Stack>
	);
}

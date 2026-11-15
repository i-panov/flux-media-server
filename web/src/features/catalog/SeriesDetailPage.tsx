import { Alert, Card, Stack, Text, Title } from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { useWork } from "../../api/catalog";
import { formatDuration } from "../../core/format";
import { clickFirstLink, useTVFocusable } from "../tv/tvFocus";

function EpisodeLink({
	mediaId,
	title,
	subtitle,
	focusKey,
}: {
	mediaId: number;
	title: string;
	subtitle?: string;
	focusKey: string;
}) {
	const { targetRef, tvMode } = useTVFocusable<HTMLDivElement>(
		focusKey,
		clickFirstLink,
	);
	return (
		<div ref={targetRef} tabIndex={tvMode ? -1 : undefined}>
			<Link
				to="/video/$id"
				params={{ id: String(mediaId) }}
				className="no-underline [color:inherit]"
			>
				<Card withBorder padding="sm" radius="md">
					<Text fw={500}>{title}</Text>
					{subtitle && (
						<Text size="xs" c="dimmed">
							{subtitle}
						</Text>
					)}
				</Card>
			</Link>
		</div>
	);
}

export function SeriesDetailPage({ id }: { id: number }) {
	const { t } = useTranslation();
	const work = useWork(id);
	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`series-detail-page-${id}`,
	);
	const { targetRef: loadingRef, tvMode: loadingTVMode } =
		useTVFocusable<HTMLDivElement>(`series-detail-loading-${id}`);

	if (work.isPending) {
		return (
			<Stack
				ref={loadingRef}
				tabIndex={loadingTVMode ? -1 : undefined}
				data-tv-page-root="true"
				data-tv-focus-key={`series-detail-loading-${id}`}
			>
				<Text c="dimmed">{t("common.loading")}</Text>
			</Stack>
		);
	}
	if (work.isError || !work.data)
		return <Alert color="red">{t("catalog.error")}</Alert>;

	const data = work.data;
	const titleOf = (title: string | undefined, fallbackID: number) =>
		title?.trim() || `#${fallbackID}`;
	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key={`series-detail-page-${id}`}
		>
			<Title order={1} size="h2">
				{data.title}
			</Title>
			{data.description && <Text c="dimmed">{data.description}</Text>}
			{data.kind === "film_series" ? (
				(data.items ?? []).length === 0 ? (
					<Text c="dimmed">{t("catalog.noFilms")}</Text>
				) : (
					<Stack gap="xs">
						{data.items?.map((item) => (
							<EpisodeLink
								key={item.id}
								mediaId={item.media_id}
								title={titleOf(item.media?.title, item.media_id)}
								focusKey={`film-item-${item.id}`}
							/>
						))}
					</Stack>
				)
			) : (data.seasons ?? []).length === 0 ? (
				<Text c="dimmed">{t("catalog.noSeasons")}</Text>
			) : (
				data.seasons?.map((season) => (
					<Stack key={season.id} gap="sm">
						<Title order={2} size="h4">
							{season.title ||
								t("catalog.season", { number: season.season_number })}
						</Title>
						{(season.items ?? []).length === 0 ? (
							<Text size="sm" c="dimmed">
								{t("catalog.noEpisodes")}
							</Text>
						) : (
							<Stack gap="xs">
								{season.items?.map((item) => (
									<EpisodeLink
										key={item.id}
										mediaId={item.media_id}
										title={`${item.episode_number == null ? "" : `${item.episode_number}. `}${titleOf(item.media?.title, item.media_id)}`}
										subtitle={
											item.media && item.media.duration > 0
												? formatDuration(item.media.duration)
												: undefined
										}
										focusKey={`episode-${item.id}`}
									/>
								))}
							</Stack>
						)}
					</Stack>
				))
			)}
		</Stack>
	);
}

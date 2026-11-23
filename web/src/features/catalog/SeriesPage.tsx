import {
	Alert,
	Group,
	MultiSelect,
	SimpleGrid,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useWorks, type WorkKind } from "../../api/catalog";
import { useSession } from "../../api/session";
import { useTags } from "../../api/tags";
import { useTVFocusable } from "../tv/tvFocus";
import { useTVMode } from "../tv/useTVMode";
import { CreateWorkButton } from "./admin/CreateWorkButton";
import { WorkCard } from "./WorkCard";

// eslint-disable-next-line complexity -- встроенный и отдельные режимы вкладок.
export function SeriesPage({
	embedded = false,
	kind,
}: {
	embedded?: boolean;
	kind?: WorkKind;
}) {
	const { t } = useTranslation();
	const [tagIDs, setTagIDs] = useState<string[]>([]);
	const tags = useTags();
	const selectedTags = tagIDs.map(Number);
	const filterTags = (tags.data ?? [])
		.filter((tag) => tag.group === "genre")
		.map((tag) => ({ value: String(tag.id), label: tag.name }));
	const series = useWorks("series", true, selectedTags);
	const films = useWorks("film_series", true, selectedTags);
	const session = useSession();
	const { capabilities } = useTVMode();
	const canManage =
		session.data?.is_admin === true && capabilities.canAccessAdmin;
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("series-page");
	const showSeries = kind !== "film_series";
	const showFilms = kind !== "series";

	const heading =
		kind === "series"
			? t("catalog.series")
			: kind === "film_series"
				? t("catalog.filmSeriesPlural")
				: t("catalog.seriesAndFilms");

	return (
		<Stack
			gap="lg"
			ref={embedded ? undefined : tvRef}
			tabIndex={!embedded && tvMode ? -1 : undefined}
			data-tv-page-root={embedded ? undefined : "true"}
			data-tv-focus-key={embedded ? undefined : "series-page"}
		>
			{kind !== undefined && (
				<Group justify="space-between" wrap="wrap" align="flex-end">
					<Group gap="sm" align="flex-end" wrap="wrap">
						<Title order={2} size="h4">
							{heading}
						</Title>
						<MultiSelect
							placeholder={t("catalog.allGenres")}
							aria-label={t("catalog.tagFilter")}
							data={filterTags}
							value={tagIDs}
							onChange={setTagIDs}
							clearable
							searchable
							nothingFoundMessage={t("video.noTags")}
							w={{ base: "100%", sm: 260 }}
						/>
					</Group>
					{canManage && <CreateWorkButton initialKind={kind} />}
				</Group>
			)}
			{kind === undefined && (
				<Group justify="space-between">
					<Title order={1} size="h2">
						{heading}
					</Title>
					{canManage && <CreateWorkButton />}
				</Group>
			)}
			{!embedded && (
				<MultiSelect
					placeholder={t("catalog.allGenres")}
					aria-label={t("catalog.tagFilter")}
					data={filterTags}
					value={tagIDs}
					onChange={setTagIDs}
					clearable
					searchable
					nothingFoundMessage={t("video.noTags")}
					w={{ base: "100%", sm: 320 }}
				/>
			)}
			{showSeries && series.isError ? (
				<Alert color="red">{t("catalog.error")}</Alert>
			) : showFilms && films.isError ? (
				<Alert color="red">{t("catalog.error")}</Alert>
			) : (
				<>
					{showSeries && (
						<Stack gap="sm">
							{kind === undefined && (
								<Title order={2} size="h4">
									{t("catalog.series")}
								</Title>
							)}
							{series.isPending ? (
								<Text c="dimmed">{t("common.loading")}</Text>
							) : (series.data ?? []).length === 0 ? (
								<Text c="dimmed">{t("catalog.emptySeries")}</Text>
							) : (
								<SimpleGrid
									cols={{ base: 2, sm: 3, md: 4, lg: 5 }}
									spacing="md"
								>
									{series.data?.map((work) => (
										<WorkCard
											key={work.id}
											work={work}
											focusPrefix="series-card"
										/>
									))}
								</SimpleGrid>
							)}
						</Stack>
					)}
					{showFilms && (
						<Stack gap="sm">
							{kind === undefined && (
								<Title order={2} size="h4">
									{t("catalog.filmSeriesPlural")}
								</Title>
							)}
							{films.isPending ? (
								<Text c="dimmed">{t("common.loading")}</Text>
							) : (films.data ?? []).length === 0 ? (
								<Text c="dimmed">{t("catalog.emptyFilms")}</Text>
							) : (
								<SimpleGrid
									cols={{ base: 2, sm: 3, md: 4, lg: 5 }}
									spacing="md"
								>
									{films.data?.map((work) => (
										<WorkCard
											key={work.id}
											work={work}
											focusPrefix="film-series-card"
										/>
									))}
								</SimpleGrid>
							)}
						</Stack>
					)}
				</>
			)}
		</Stack>
	);
}

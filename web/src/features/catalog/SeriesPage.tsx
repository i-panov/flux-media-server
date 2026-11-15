import { Alert, SimpleGrid, Stack, Text, Title } from "@mantine/core";
import { useTranslation } from "react-i18next";
import { useWorks } from "../../api/catalog";
import { useTVFocusable } from "../tv/tvFocus";
import { WorkCard } from "./WorkCard";

export function SeriesPage() {
	const { t } = useTranslation();
	const series = useWorks("series");
	const films = useWorks("film_series");
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("series-page");

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="series-page"
		>
			<Title order={1} size="h2">
				{t("catalog.seriesAndFilms")}
			</Title>
			{series.isError || films.isError ? (
				<Alert color="red">{t("catalog.error")}</Alert>
			) : (
				<>
					<Stack gap="sm">
						<Title order={2} size="h4">
							{t("catalog.series")}
						</Title>
						{series.isPending ? (
							<Text c="dimmed">{t("common.loading")}</Text>
						) : (series.data ?? []).length === 0 ? (
							<Text c="dimmed">{t("catalog.emptySeries")}</Text>
						) : (
							<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5 }} spacing="md">
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
					<Stack gap="sm">
						<Title order={2} size="h4">
							{t("catalog.filmSeriesPlural")}
						</Title>
						{films.isPending ? (
							<Text c="dimmed">{t("common.loading")}</Text>
						) : (films.data ?? []).length === 0 ? (
							<Text c="dimmed">{t("catalog.emptyFilms")}</Text>
						) : (
							<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5 }} spacing="md">
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
				</>
			)}
		</Stack>
	);
}

import { Alert, Card, Stack, Text, Title } from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { useFranchise } from "../../api/catalog";
import { clickFirstLink, useTVFocusable } from "../tv/tvFocus";

function EntryCard({
	title,
	label,
	link,
	focusKey,
}: {
	title: string;
	label: string;
	link: { to: "/series/$id" | "/video/$id"; id: number };
	focusKey: string;
}) {
	const { targetRef, tvMode } = useTVFocusable<HTMLDivElement>(
		focusKey,
		clickFirstLink,
	);
	return (
		<div ref={targetRef} tabIndex={tvMode ? -1 : undefined}>
			<Link
				to={link.to}
				params={{ id: String(link.id) }}
				className="no-underline [color:inherit]"
			>
				<Card withBorder padding="sm" radius="md">
					<Text fw={500}>{title}</Text>
					<Text size="xs" c="dimmed">
						{label}
					</Text>
				</Card>
			</Link>
		</div>
	);
}

export function FranchiseDetailPage({ id }: { id: number }) {
	const { t } = useTranslation();
	const franchise = useFranchise(id);
	const { targetRef: tvRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`franchise-detail-page-${id}`,
	);
	const { targetRef: loadingRef, tvMode: loadingTVMode } =
		useTVFocusable<HTMLDivElement>(`franchise-detail-loading-${id}`);
	if (franchise.isPending) {
		return (
			<Stack
				ref={loadingRef}
				tabIndex={loadingTVMode ? -1 : undefined}
				data-tv-page-root="true"
				data-tv-focus-key={`franchise-detail-loading-${id}`}
			>
				<Text c="dimmed">{t("common.loading")}</Text>
			</Stack>
		);
	}
	if (franchise.isError || !franchise.data)
		return <Alert color="red">{t("catalog.error")}</Alert>;

	const data = franchise.data;
	const visible = (data.entries ?? []).filter(
		(entry) => entry.work != null || entry.media_id != null,
	);
	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key={`franchise-detail-page-${id}`}
		>
			<Title order={1} size="h2">
				{data.name}
			</Title>
			{data.description && <Text c="dimmed">{data.description}</Text>}
			{visible.length === 0 ? (
				<Text c="dimmed">{t("catalog.emptyFranchise")}</Text>
			) : (
				<Stack gap="xs">
					{visible.map((entry) => {
						if (entry.work) {
							const isSeries = entry.work.kind === "series";
							const title = entry.work.title?.trim() || `#${entry.work.id}`;
							return (
								<EntryCard
									key={entry.id}
									title={title}
									label={
										isSeries ? t("catalog.seriesOne") : t("catalog.filmSeries")
									}
									link={{ to: "/series/$id", id: entry.work.id }}
									focusKey={`franchise-entry-${entry.id}`}
								/>
							);
						}
						const mediaID = entry.media_id ?? entry.media?.id ?? 0;
						const title = entry.media?.title?.trim() || `#${mediaID}`;
						return (
							<EntryCard
								key={entry.id}
								title={title}
								label={t("catalog.movie")}
								link={{ to: "/video/$id", id: mediaID }}
								focusKey={`franchise-entry-${entry.id}`}
							/>
						);
					})}
				</Stack>
			)}
		</Stack>
	);
}

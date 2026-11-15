import { Card, Text } from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { Clapperboard, Tv } from "lucide-react";
import { useTranslation } from "react-i18next";
import type { CatalogWork } from "../../api/catalog";
import { clickFirstLink, useTVFocusable } from "../tv/tvFocus";

export function WorkCard({
	work,
	focusPrefix,
}: {
	work: CatalogWork;
	focusPrefix: string;
}) {
	const { t } = useTranslation();
	const { targetRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`${focusPrefix}-${work.id}`,
		clickFirstLink,
	);
	const Icon = work.kind === "series" ? Tv : Clapperboard;
	return (
		<div ref={targetRef} tabIndex={tvMode ? -1 : undefined} className="h-full">
			<Link
				to="/series/$id"
				params={{ id: String(work.id) }}
				className="block h-full no-underline [color:inherit]"
			>
				<Card withBorder padding="sm" radius="md" h="100%">
					<Card.Section>
						{work.cover_url ? (
							<img
								src={work.cover_url}
								alt={work.title}
								loading="lazy"
								className="aspect-video w-full object-cover"
							/>
						) : (
							<div className="grid aspect-video w-full place-items-center bg-[var(--mantine-color-default-hover)]">
								<Icon size={32} />
							</div>
						)}
					</Card.Section>
					<Text fw={600} mt="xs" lineClamp={2}>
						{work.title}
					</Text>
					<Text size="xs" c="dimmed">
						{work.year > 0 ? work.year : t("common.emptyFallback")}
					</Text>
				</Card>
			</Link>
		</div>
	);
}

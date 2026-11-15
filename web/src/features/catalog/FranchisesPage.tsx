import {
	Alert,
	Card,
	Group,
	SimpleGrid,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { Clapperboard } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useFranchises } from "../../api/catalog";
import { useSession } from "../../api/session";
import { clickFirstLink, useTVFocusable } from "../tv/tvFocus";
import { useTVMode } from "../tv/useTVMode";
import { CreateFranchiseButton } from "./admin/CreateFranchiseButton";

function FranchiseCard({
	id,
	name,
	coverURL,
}: {
	id: number;
	name: string;
	coverURL: string;
}) {
	const { targetRef, tvMode } = useTVFocusable<HTMLDivElement>(
		`franchise-card-${id}`,
		clickFirstLink,
	);
	return (
		<div ref={targetRef} tabIndex={tvMode ? -1 : undefined}>
			<Link
				to="/franchises/$id"
				params={{ id: String(id) }}
				className="no-underline [color:inherit]"
			>
				<Card withBorder padding="sm" radius="md" h="100%">
					<Card.Section>
						{coverURL ? (
							<img
								src={coverURL}
								alt={name}
								loading="lazy"
								className="aspect-video w-full object-cover"
							/>
						) : (
							<div className="grid aspect-video w-full place-items-center bg-[var(--mantine-color-default-hover)]">
								<Clapperboard size={32} />
							</div>
						)}
					</Card.Section>
					<Text fw={600} mt="xs" lineClamp={2}>
						{name.trim() || `#${id}`}
					</Text>
				</Card>
			</Link>
		</div>
	);
}

export function FranchisesPage() {
	const { t } = useTranslation();
	const franchises = useFranchises();
	const session = useSession();
	const { capabilities } = useTVMode();
	const canManage =
		session.data?.is_admin === true && capabilities.canAccessAdmin;
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("franchises-page");
	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="franchises-page"
		>
			<Group justify="space-between">
				<Title order={1} size="h2">
					{t("catalog.franchises")}
				</Title>
				{canManage && <CreateFranchiseButton />}
			</Group>
			{franchises.isPending ? (
				<Text c="dimmed">{t("common.loading")}</Text>
			) : franchises.isError ? (
				<Alert color="red">{t("catalog.error")}</Alert>
			) : (franchises.data ?? []).length === 0 ? (
				<Text c="dimmed">{t("catalog.emptyFranchises")}</Text>
			) : (
				<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5 }} spacing="md">
					{franchises.data?.map((franchise) => (
						<FranchiseCard
							key={franchise.id}
							id={franchise.id}
							name={franchise.name}
							coverURL={franchise.cover_url}
						/>
					))}
				</SimpleGrid>
			)}
		</Stack>
	);
}

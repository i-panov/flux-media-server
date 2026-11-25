import {
	Alert,
	Button,
	Card,
	Image,
	SimpleGrid,
	Skeleton,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { Link } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { useMediaArtists } from "../../api/metadata";

// Список всех артистов: на web раньше были только избранные и deep link.
export function ArtistsPage() {
	const { t } = useTranslation();
	const artists = useMediaArtists();

	return (
		<Stack gap="lg">
			<Title order={1} size="h2">
				{t("artists.title")}
			</Title>
			{artists.isPending ? (
				<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5 }} spacing="md">
					{Array.from({ length: 10 }, (_, index) => `skeleton-${index}`).map(
						(key) => (
							<Skeleton key={key} height={180} radius="md" />
						),
					)}
				</SimpleGrid>
			) : artists.isError ? (
				<Alert color="red" variant="light" title={t("artists.loadError")}>
					<Button
						variant="light"
						size="xs"
						mt="xs"
						onClick={() => {
							void artists.refetch();
						}}
					>
						{t("common.retry")}
					</Button>
				</Alert>
			) : (artists.data ?? []).length === 0 ? (
				<Text c="dimmed">{t("artists.empty")}</Text>
			) : (
				<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5 }} spacing="md">
					{(artists.data ?? []).map((artist) => (
						<Card key={artist.id} withBorder padding="sm" radius="md">
							<Link
								to="/artists/$id"
								params={{ id: String(artist.id) }}
								style={{ textDecoration: "none", color: "inherit" }}
							>
								<Card.Section>
									{artist.has_cover ? (
										<Image
											src={`/api/artists/${artist.id}/cover?v=${encodeURIComponent(artist.updated_at)}`}
											alt={artist.name}
											h={150}
											fit="cover"
										/>
									) : (
										<div className="grid h-[150px] place-items-center bg-[var(--mantine-color-default-hover)]">
											<Text size="xl" fw={600} c="dimmed">
												{artist.name.slice(0, 1).toUpperCase()}
											</Text>
										</div>
									)}
								</Card.Section>
								<Text mt="xs" fw={600} lineClamp={2}>
									{artist.name}
								</Text>
							</Link>
						</Card>
					))}
				</SimpleGrid>
			)}
		</Stack>
	);
}

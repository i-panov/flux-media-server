import { Badge, SimpleGrid, Stack, Text, Title } from "@mantine/core";
import { useTranslation } from "react-i18next";
import { AboutCard } from "../../components/AboutCard";
import { HealthCard } from "../../components/HealthCard";
import { NextCard } from "../../components/NextCard";
import { ContinueWatching } from "../media/ContinueWatching";
import { TVFocusScope, useTVFocusable } from "../tv/tvFocus";

// На главной хватает превью: полные списки живут в разделах «Видео» и «Аудио».
const CONTINUE_PREVIEW_LIMIT = 6;

export function HomePage() {
	const { t } = useTranslation();
	// ТВ-режим: только сетка продолжения — остальные карточки нативные.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("home-page");

	return (
		<Stack
			gap="xl"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-focus-key="home-page"
		>
			<Stack gap="xs">
				<Badge variant="light" color="violet" w="fit-content">
					PWA
				</Badge>
				<Title order={1} fz={{ base: 40, sm: 56 }} fw={700}>
					Flux
				</Title>
				<Text size="xl" c="dimmed">
					{t("home.subtitle")}
				</Text>
				<Text>{t("home.description")}</Text>
			</Stack>

			<TVFocusScope focusKey="home-page">
				<ContinueWatching limit={CONTINUE_PREVIEW_LIMIT} />
			</TVFocusScope>

			<SimpleGrid cols={{ base: 1, md: 2 }}>
				<HealthCard />
				<AboutCard />
			</SimpleGrid>

			<NextCard />
		</Stack>
	);
}

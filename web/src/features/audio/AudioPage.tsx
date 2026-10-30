import {
	Alert,
	Button,
	Group,
	SimpleGrid,
	Skeleton,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useFavoriteMedia } from "../../api/favorites";
import { useAudioList } from "../../api/media";
import { useSession } from "../../api/session";
import { CollectionsSection } from "../collections/CollectionsSection";
import { FavoriteArtistsSection } from "../favorites/FavoriteArtistsSection";
import { FavoriteSection } from "../favorites/FavoriteSection";
import { useAudioPlayer } from "../player/AudioPlayerProvider";
import { UploadButton } from "../upload/UploadButton";
import { AudioTrackRow } from "./AudioTrackRow";

const SKELETON_COUNT = 12;
const SEARCH_DEBOUNCE_MS = 300;

function AudioSkeletons() {
	return (
		<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }} spacing="md">
			{Array.from({ length: SKELETON_COUNT }, (_, index) => (
				// Скелетоны без данных: индекс здесь — стабильный
				// идентификатор позиции, а не сущности.
				// biome-ignore lint/suspicious/noArrayIndexKey: skeleton placeholder
				<Stack key={index} gap="xs">
					<Skeleton height={160} radius="md" />
					<Skeleton height={14} width="80%" radius="sm" />
					<Skeleton height={12} width="50%" radius="sm" />
				</Stack>
			))}
		</SimpleGrid>
	);
}

export function AudioPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const player = useAudioPlayer();
	const [query, setQuery] = useState("");
	const [debounced, setDebounced] = useState("");

	useEffect(() => {
		const timer = setTimeout(() => {
			setDebounced(query.trim());
		}, SEARCH_DEBOUNCE_MS);
		return () => {
			clearTimeout(timer);
		};
	}, [query]);

	const list = useAudioList(debounced);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const { data: session } = useSession();
	const isAdmin = session?.is_admin === true;
	const favoriteMedia = useFavoriteMedia("audio");
	const favoriteSectionIds = new Set(favoriteMedia.map((media) => media.id));
	const visibleItems =
		debounced === ""
			? items.filter((media) => !favoriteSectionIds.has(media.id))
			: items;

	return (
		<Stack gap="lg">
			<Group justify="space-between" align="center" wrap="wrap">
				<Title order={1} size="h2">
					{t("audio.title")}
				</Title>
				<UploadButton type="audio" />
			</Group>
			<TextInput
				placeholder={t("audio.search")}
				aria-label={t("audio.search")}
				value={query}
				onChange={(event) => {
					setQuery(event.currentTarget.value);
				}}
				w={{ base: "100%", sm: 320 }}
			/>
			{/* При поиске секции не нужны: они не фильтруются.
			Блока продолжения здесь нет: недослушанный трек поднимается
			мини-плеером на паузе сразу после загрузки. */}
			{debounced === "" && <FavoriteSection type="audio" />}
			{debounced === "" && (
				<FavoriteArtistsSection onSelect={(name) => setQuery(name)} />
			)}
			{debounced === "" && <CollectionsSection type="audio" />}
			{list.isPending ? (
				<AudioSkeletons />
			) : list.isError && items.length === 0 ? (
				<Alert color="red" variant="light" title={t("audio.error")}>
					<Button
						variant="light"
						size="xs"
						mt="xs"
						onClick={() => {
							void list.refetch();
						}}
					>
						{t("common.retry")}
					</Button>
				</Alert>
			) : items.length === 0 ? (
				<Text c="dimmed">{t("audio.empty")}</Text>
			) : (
				<>
					<Stack gap="xs">
						{visibleItems.map((media) => (
							<AudioTrackRow
								key={media.id}
								media={media}
								onPlay={() => {
									player.playQueue(items, items.indexOf(media));
									void navigate({ to: "/player" });
								}}
								showDelete={isAdmin}
							/>
						))}
					</Stack>
					{list.isFetchNextPageError ? (
						<Alert color="red" variant="light" title={t("audio.error")}>
							<Button
								variant="light"
								size="xs"
								mt="xs"
								onClick={() => {
									void list.fetchNextPage();
								}}
							>
								{t("common.retry")}
							</Button>
						</Alert>
					) : (
						list.hasNextPage && (
							<Button
								variant="light"
								w="fit-content"
								loading={list.isFetchingNextPage}
								onClick={() => {
									void list.fetchNextPage();
								}}
							>
								{t("audio.loadMore")}
							</Button>
						)
					)}
				</>
			)}
		</Stack>
	);
}

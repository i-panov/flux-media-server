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
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useFavoriteMedia } from "../../api/favorites";
import { useImageList } from "../../api/media";
import { CollectionsSection } from "../collections/CollectionsSection";
import { FavoriteSection } from "../favorites/FavoriteSection";
import { UploadButton } from "../upload/UploadButton";
import { MemeCard } from "./MemeCard";

const SKELETON_COUNT = 12;
const SEARCH_DEBOUNCE_MS = 300;

function MemeSkeletons() {
	return (
		<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }} spacing="md">
			{Array.from({ length: SKELETON_COUNT }, (_, index) => (
				// Индекс — стабильный идентификатор позиции скелетона.
				// biome-ignore lint/suspicious/noArrayIndexKey: skeleton placeholder
				<Skeleton key={index} className="aspect-square" radius="md" />
			))}
		</SimpleGrid>
	);
}

export function MemesPage() {
	const { t } = useTranslation();
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

	const list = useImageList(debounced);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const favoriteMedia = useFavoriteMedia("image");
	const favoriteSectionIds = new Set(favoriteMedia.map((media) => media.id));
	const visibleItems =
		debounced === ""
			? items.filter((media) => !favoriteSectionIds.has(media.id))
			: items;

	return (
		<Stack gap="lg">
			<Group justify="space-between" align="center" wrap="wrap">
				<Title order={1} size="h2">
					{t("memes.title")}
				</Title>
				<UploadButton type="image" />
			</Group>
			<TextInput
				placeholder={t("memes.search")}
				aria-label={t("memes.search")}
				value={query}
				onChange={(event) => {
					setQuery(event.currentTarget.value);
				}}
				w={{ base: "100%", sm: 320 }}
			/>
			{debounced === "" && <FavoriteSection type="image" />}
			{debounced === "" && <CollectionsSection type="image" />}
			{list.isPending ? (
				<MemeSkeletons />
			) : list.isError && items.length === 0 ? (
				<Alert color="red" variant="light" title={t("memes.error")}>
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
				<Text c="dimmed">{t("memes.empty")}</Text>
			) : (
				<>
					<SimpleGrid
						cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }}
						spacing="md"
					>
						{visibleItems.map((media) => (
							<MemeCard key={media.id} media={media} />
						))}
					</SimpleGrid>
					{list.isFetchNextPageError ? (
						<Alert color="red" variant="light" title={t("memes.error")}>
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
								{t("memes.loadMore")}
							</Button>
						)
					)}
				</>
			)}
		</Stack>
	);
}

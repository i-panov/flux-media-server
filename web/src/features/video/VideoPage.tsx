import {
	Alert,
	Button,
	Group,
	SimpleGrid,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useVideoList } from "../../api/media";
import { CardGridSkeletons } from "../../components/CardGridSkeletons";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";
import { useVisibleMedia } from "../../hooks/useVisibleMedia";
import { CollectionsSection } from "../collections/CollectionsSection";
import { FavoriteSection } from "../favorites/FavoriteSection";
import { ContinueWatching } from "../media/ContinueWatching";
import { UploadButton } from "../upload/UploadButton";
import { VideoCard } from "./VideoCard";

export function VideoPage() {
	const { t } = useTranslation();
	const [query, setQuery] = useState("");
	const debounced = useDebouncedValue(query);

	const list = useVideoList(debounced);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const visibleItems = useVisibleMedia("video", items, debounced !== "");

	return (
		<Stack gap="lg">
			<Group justify="space-between" align="center" wrap="wrap">
				<Title order={1} size="h2">
					{t("video.title")}
				</Title>
				<UploadButton type="video" />
			</Group>
			<TextInput
				placeholder={t("video.search")}
				aria-label={t("video.search")}
				value={query}
				onChange={(event) => {
					setQuery(event.currentTarget.value);
				}}
				w={{ base: "100%", sm: 320 }}
			/>
			{/* При поиске ряды продолжения не нужны: они не фильтруются. */}
			{debounced === "" && <ContinueWatching limit={1} />}
			{debounced === "" && <FavoriteSection type="video" />}
			{debounced === "" && <CollectionsSection type="video" />}
			{list.isPending ? (
				<CardGridSkeletons />
			) : list.isError && items.length === 0 ? (
				<Alert color="red" variant="light" title={t("video.error")}>
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
				<Text c="dimmed">{t("video.empty")}</Text>
			) : (
				<>
					<SimpleGrid
						cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }}
						spacing="md"
					>
						{visibleItems.map((media) => (
							<VideoCard key={media.id} media={media} />
						))}
					</SimpleGrid>
					{list.isFetchNextPageError ? (
						<Alert color="red" variant="light" title={t("video.error")}>
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
								{t("video.loadMore")}
							</Button>
						)
					)}
				</>
			)}
		</Stack>
	);
}

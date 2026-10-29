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
import { useVideoList } from "../../api/media";
import { ContinueWatching } from "../media/ContinueWatching";
import { UploadButton } from "../upload/UploadButton";
import { VideoCard } from "./VideoCard";

const SKELETON_COUNT = 12;
const SEARCH_DEBOUNCE_MS = 300;

function VideoSkeletons() {
	return (
		<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }} spacing="md">
			{Array.from({ length: SKELETON_COUNT }, (_, index) => (
				// Скелетоны без данных: индекс здесь — стабильный
				// идентификатор позиции, а не сущности.
				// biome-ignore lint/suspicious/noArrayIndexKey: skeleton placeholder
				<Stack key={index} gap="xs">
					<Skeleton height={140} radius="md" />
					<Skeleton height={14} width="80%" radius="sm" />
				</Stack>
			))}
		</SimpleGrid>
	);
}

export function VideoPage() {
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

	const list = useVideoList(debounced);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];

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
			{debounced === "" && <ContinueWatching kind="video" />}
			{list.isPending ? (
				<VideoSkeletons />
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
						{items.map((media) => (
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

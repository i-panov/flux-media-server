import {
	Alert,
	Button,
	SimpleGrid,
	Skeleton,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useImageList } from "../../api/media";
import { MemeCard } from "./MemeCard";

const SKELETON_COUNT = 12;
const SEARCH_DEBOUNCE_MS = 300;

function MemeSkeletons() {
	return (
		<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5 }} spacing="md">
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

	return (
		<Stack gap="lg">
			<Title order={1} size="h2">
				{t("memes.title")}
			</Title>
			<TextInput
				placeholder={t("memes.search")}
				aria-label={t("memes.search")}
				value={query}
				onChange={(event) => {
					setQuery(event.currentTarget.value);
				}}
				w={{ base: "100%", sm: 320 }}
			/>
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
					<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5 }} spacing="md">
						{items.map((media) => (
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

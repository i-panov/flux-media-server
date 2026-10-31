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
import { useImageList } from "../../api/media";
import { CardGridSkeletons } from "../../components/CardGridSkeletons";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";
import { useVisibleMedia } from "../../hooks/useVisibleMedia";
import { CollectionsSection } from "../collections/CollectionsSection";
import { FavoriteSection } from "../favorites/FavoriteSection";
import { TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { UploadButton } from "../upload/UploadButton";
import { MemeCard } from "./MemeCard";

export function MemesPage() {
	const { t } = useTranslation();
	const [query, setQuery] = useState("");
	const debounced = useDebouncedValue(query);
	// ТВ-режим: корень — spatial-секция, плитки внутри — цели навигации.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("memes-page");

	const list = useImageList(debounced);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const visibleItems = useVisibleMedia("image", items, debounced !== "");

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-focus-key="memes-page"
		>
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
				<CardGridSkeletons square textLines={0} />
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
				<TVFocusScope focusKey="memes-page">
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
				</TVFocusScope>
			)}
		</Stack>
	);
}

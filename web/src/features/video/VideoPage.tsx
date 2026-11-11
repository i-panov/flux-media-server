import {
	Alert,
	Button,
	Group,
	SegmentedControl,
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
import { TVButton, TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { UploadButton } from "../upload/UploadButton";
import { VideoCard } from "./VideoCard";

export function VideoPage() {
	const { t } = useTranslation();
	const [query, setQuery] = useState("");
	const [sort, setSort] = useState<"desc" | "asc">("desc");
	const debounced = useDebouncedValue(query);
	// ТВ-режим: корень страницы — spatial-секция, ref на существующем Stack
	// (вёрстка не меняется), карточки внутри — цели навигации.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("video-page");
	const { targetRef: searchRef } = useTVFocusable<HTMLInputElement>(
		"video-search",
		undefined,
		undefined,
		{ secondary: true },
	);
	const { targetRef: sortRef } = useTVFocusable<HTMLDivElement>(
		"video-sort",
		() => setSort((prev) => (prev === "asc" ? "desc" : "asc")),
		undefined,
		{ secondary: true },
	);

	const list = useVideoList(debounced, sort);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const visibleItems = useVisibleMedia("video", items, debounced !== "");

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="video-page"
		>
			<Group justify="space-between" align="center" wrap="wrap">
				<Title order={1} size="h2">
					{t("video.title")}
				</Title>
				<UploadButton type="video" />
			</Group>
			<Group gap="sm" wrap="wrap">
				<TextInput
					ref={searchRef}
					placeholder={t("video.search")}
					aria-label={t("video.search")}
					value={query}
					onChange={(event) => {
						setQuery(event.currentTarget.value);
					}}
					w={{ base: "100%", sm: 320 }}
				/>
				<div ref={sortRef} tabIndex={tvMode ? -1 : undefined}>
					<SegmentedControl
						size="xs"
						value={sort}
						onChange={(value) => setSort(value === "asc" ? "asc" : "desc")}
						data={[
							{ value: "desc", label: t("common.newest") },
							{ value: "asc", label: t("common.oldest") },
						]}
					/>
				</div>
			</Group>
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
				<TVFocusScope focusKey="video-page">
					{debounced === "" && (
						<Title order={2} size="h4">
							{t("video.all")}
						</Title>
					)}
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
							<TVButton
								focusKey="video-load-more"
								variant="light"
								w="fit-content"
								loading={list.isFetchingNextPage}
								onClick={() => {
									void list.fetchNextPage();
								}}
							>
								{t("video.loadMore")}
							</TVButton>
						)
					)}
				</TVFocusScope>
			)}
		</Stack>
	);
}

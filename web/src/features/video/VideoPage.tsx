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
import { setFocus } from "@noriginmedia/norigin-spatial-navigation";
import { useNavigate, useSearch } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useVideoList } from "../../api/media";
import { CardGridSkeletons } from "../../components/CardGridSkeletons";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";
import { useVisibleMedia } from "../../hooks/useVisibleMedia";
import { FranchisesPage } from "../catalog/FranchisesPage";
import { SeriesPage } from "../catalog/SeriesPage";
import { CollectionsSection } from "../collections/CollectionsSection";
import { LEGACY_COLLECTIONS_ENABLED } from "../collections/legacy";
import { FavoriteSection } from "../favorites/FavoriteSection";
import { ContinueWatching } from "../media/ContinueWatching";
import { TVButton, TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { UploadButton } from "../upload/UploadButton";
import { VideoCard } from "./VideoCard";

type VideoTab = "movies" | "series" | "franchises";

function VideoTabButton({
	focusKey,
	value,
	onSelect,
	active,
	onDown,
	children,
}: {
	focusKey: string;
	value: VideoTab;
	onSelect: (value: VideoTab) => void;
	active: boolean;
	onDown: () => boolean;
	children: React.ReactNode;
}) {
	const { targetRef } = useTVFocusable<HTMLButtonElement>(
		focusKey,
		() => onSelect(value),
		(direction) => {
			if (direction === "down") {
				return onDown();
			}
			const order: VideoTab[] = ["movies", "series", "franchises"];
			const index = order.indexOf(value);
			const target =
				direction === "right"
					? order[index + 1]
					: direction === "left"
						? order[index - 1]
						: undefined;
			if (target === undefined) {
				return false;
			}
			void setFocus(`video-tab-${target}`);
			return true;
		},
	);
	return (
		<Button
			ref={targetRef}
			role="tab"
			aria-selected={active}
			variant={active ? "filled" : "default"}
			onClick={() => onSelect(value)}
		>
			{children}
		</Button>
	);
}

// Legacy-коллекции скрыты из основного UI: каталог сериалов/франшиз
// заменяет их. Прямые маршруты /collections остаются для старых ссылок.
export function VideoPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion -- tab живёт в search, но общий SearchSchema его не знает.
	const search = useSearch({ strict: false }) as { tab?: string };
	const tab: VideoTab =
		search.tab === "series"
			? "series"
			: search.tab === "franchises"
				? "franchises"
				: "movies";
	const setTab = (value: VideoTab) => {
		void navigate({
			to: "/video",
			search: {
				...search,
				tab: value === "movies" ? undefined : value,
			},
		});
	};

	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("video-page");
	const focusFirstCard = () => {
		const selector =
			tab === "series"
				? '[data-tv-focus-key^="series-card-"], [data-tv-focus-key^="film-series-card-"]'
				: tab === "franchises"
					? '[data-tv-focus-key^="franchise-card-"]'
					: '[data-tv-focus-key^="video-card-"]';
		const node = document.querySelector<HTMLElement>(selector);
		const key = node?.getAttribute("data-tv-focus-key");
		if (key === null || key === undefined) return false;
		void setFocus(key);
		return true;
	};

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
			<Group role="tablist" aria-label={t("catalog.tabs")} gap="xs">
				<VideoTabButton
					focusKey="video-tab-movies"
					value="movies"
					onSelect={setTab}
					active={tab === "movies"}
					onDown={focusFirstCard}
				>
					{t("catalog.movies")}
				</VideoTabButton>
				<VideoTabButton
					focusKey="video-tab-series"
					value="series"
					onSelect={setTab}
					active={tab === "series"}
					onDown={focusFirstCard}
				>
					{t("catalog.series")}
				</VideoTabButton>
				<VideoTabButton
					focusKey="video-tab-franchises"
					value="franchises"
					onSelect={setTab}
					active={tab === "franchises"}
					onDown={focusFirstCard}
				>
					{t("catalog.franchises")}
				</VideoTabButton>
			</Group>
			{tab === "movies" ? (
				<MoviesContent />
			) : tab === "series" ? (
				<SeriesPage embedded />
			) : (
				<FranchisesPage embedded />
			)}
		</Stack>
	);
}

function MoviesContent() {
	const { t } = useTranslation();
	const [query, setQuery] = useState("");
	const [sort, setSort] = useState<"desc" | "asc">("desc");
	const debounced = useDebouncedValue(query);
	const { targetRef: searchRef } = useTVFocusable<HTMLInputElement>(
		"video-search",
		undefined,
		undefined,
		{ secondary: true },
	);
	const { targetRef: sortRef, tvMode } = useTVFocusable<HTMLDivElement>(
		"video-sort",
		() => setSort((prev) => (prev === "asc" ? "desc" : "asc")),
		undefined,
		{ secondary: true },
	);
	const list = useVideoList(debounced, sort);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const visibleItems = useVisibleMedia("video", items, debounced !== "");

	return (
		<>
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
			{debounced === "" && <ContinueWatching limit={1} />}
			{debounced === "" && <FavoriteSection type="video" />}
			{LEGACY_COLLECTIONS_ENABLED && debounced === "" && (
				<CollectionsSection type="video" />
			)}
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
		</>
	);
}

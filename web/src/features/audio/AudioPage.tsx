import {
	Alert,
	Button,
	Group,
	SegmentedControl,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useAudioList } from "../../api/media";
import { useSession } from "../../api/session";
import { CardGridSkeletons } from "../../components/CardGridSkeletons";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";
import { useVisibleMedia } from "../../hooks/useVisibleMedia";
import { CollectionsSection } from "../collections/CollectionsSection";
import { FavoriteArtistsSection } from "../favorites/FavoriteArtistsSection";
import { FavoriteSection } from "../favorites/FavoriteSection";
import { useAudioPlayer } from "../player/AudioPlayerProvider";
import { TVButton, TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { useTVMode } from "../tv/useTVMode";
import { UploadButton } from "../upload/UploadButton";
import { AudioTrackRow } from "./AudioTrackRow";

export function AudioPage() {
	const { t } = useTranslation();
	const player = useAudioPlayer();
	const [query, setQuery] = useState("");
	const [sort, setSort] = useState<"desc" | "asc">("desc");
	const debounced = useDebouncedValue(query);
	// ТВ-режим: корень — spatial-секция, строки внутри — цели навигации.
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("audio-page");
	const { targetRef: searchRef } = useTVFocusable<HTMLInputElement>(
		"audio-search",
		undefined,
		undefined,
		{ secondary: true },
	);
	const { targetRef: sortRef } = useTVFocusable<HTMLDivElement>(
		"audio-sort",
		() => setSort((prev) => (prev === "asc" ? "desc" : "asc")),
		undefined,
		{ secondary: true },
	);

	const list = useAudioList(debounced, undefined, true, sort);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const { data: session } = useSession();
	const isAdmin = session?.is_admin === true;
	const { capabilities } = useTVMode();
	const visibleItems = useVisibleMedia("audio", items, debounced !== "");

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="audio-page"
		>
			<Group justify="space-between" align="center" wrap="wrap">
				<Title order={1} size="h2">
					{t("audio.title")}
				</Title>
				<UploadButton type="audio" />
			</Group>
			<Group gap="sm" wrap="wrap">
				<TextInput
					ref={searchRef}
					placeholder={t("audio.search")}
					aria-label={t("audio.search")}
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
			{/* При поиске секции не нужны: они не фильтруются.
			Блока продолжения здесь нет: недослушанный трек поднимается
			мини-плеером на паузе сразу после загрузки. */}
			{debounced === "" && <FavoriteSection type="audio" />}
			{debounced === "" && (
				<FavoriteArtistsSection onSelect={(name) => setQuery(name)} />
			)}
			{debounced === "" && <CollectionsSection type="audio" />}
			{list.isPending ? (
				<CardGridSkeletons imageHeight={160} textLines={2} />
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
				<TVFocusScope focusKey="audio-page">
					{debounced === "" && (
						<Title order={2} size="h4">
							{t("audio.all")}
						</Title>
					)}
					<Stack gap="xs">
						{visibleItems.map((media, index) => (
							<AudioTrackRow
								key={media.id}
								media={media}
								onPlay={() => {
									if (player.current?.id === media.id) {
										player.toggle();
										return;
									}
									// Клик по строке запускает мини-плеер; полный
									// плеер открывается кликом по названию в нём.
									player.playQueue(visibleItems, index);
								}}
								showDelete={isAdmin && capabilities.canDelete}
								isCurrent={player.current?.id === media.id}
								isPlaying={player.playing}
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
							<TVButton
								focusKey="audio-load-more"
								variant="light"
								w="fit-content"
								loading={list.isFetchingNextPage}
								onClick={() => {
									void list.fetchNextPage();
								}}
							>
								{t("audio.loadMore")}
							</TVButton>
						)
					)}
				</TVFocusScope>
			)}
		</Stack>
	);
}

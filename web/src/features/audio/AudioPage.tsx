import {
	Alert,
	Button,
	Group,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
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
import { UploadButton } from "../upload/UploadButton";
import { AudioTrackRow } from "./AudioTrackRow";

export function AudioPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const player = useAudioPlayer();
	const [query, setQuery] = useState("");
	const debounced = useDebouncedValue(query);

	const list = useAudioList(debounced);
	const items = list.data?.pages.flatMap((page) => page.items) ?? [];
	const { data: session } = useSession();
	const isAdmin = session?.is_admin === true;
	const visibleItems = useVisibleMedia("audio", items, debounced !== "");

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
				<>
					<Stack gap="xs">
						{visibleItems.map((media, index) => (
							<AudioTrackRow
								key={media.id}
								media={media}
								onPlay={() => {
									player.playQueue(visibleItems, index);
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

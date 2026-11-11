import {
	Alert,
	Button,
	Group,
	Modal,
	Stack,
	Text,
	TextInput,
} from "@mantine/core";
import { infiniteQueryOptions, useInfiniteQuery } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { apiFetch } from "../../api/client";
import { useAddToCollection } from "../../api/collections";
import type { CoreFetcher, MediaType } from "../../core/media";
import { fetchMediaList } from "../../core/media";
import { useDebouncedValue } from "../../hooks/useDebouncedValue";
import { TVButton, TVModalAutoFocus } from "../tv/tvFocus";
import { useCollectionError } from "./useCollectionError";

const PICKER_PAGE_SIZE = 50;

// Постраничный пикер: тот же контракт, что mediaListOptions в ядре
// (пустая страница останавливает пагинацию), но свой ключ, размер
// страницы и поисковая строка.
function pickerListOptions(
	fetch: CoreFetcher,
	type: MediaType,
	q: string,
	enabled: boolean,
) {
	return infiniteQueryOptions({
		queryKey: ["media", "picker", type, q],
		queryFn: ({ pageParam, signal }) =>
			fetchMediaList(fetch, {
				type,
				q,
				limit: PICKER_PAGE_SIZE,
				offset: pageParam,
				signal,
			}),
		initialPageParam: 0,
		getNextPageParam: (lastPage, _allPages, lastOffset) => {
			// Пустая страница при total > offset (гонка с удалением):
			// тот же offset запросился бы снова — останавливаемся.
			if (lastPage.items.length === 0) {
				return;
			}
			const fetched = lastOffset + lastPage.items.length;
			return fetched < lastPage.total ? fetched : undefined;
		},
		retry: false,
		refetchOnWindowFocus: false,
		enabled,
	});
}

export function AddMediaToCollectionModal({
	opened,
	collectionId,
	type,
	existingIds,
	onClose,
}: {
	opened: boolean;
	collectionId: number;
	type: MediaType;
	existingIds: Set<number>;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const [query, setQuery] = useState("");
	const debounced = useDebouncedValue(query);
	const add = useAddToCollection();
	const notifyError = useCollectionError();

	const list = useInfiniteQuery(
		pickerListOptions(apiFetch, type, debounced, opened),
	);

	const items = (list.data?.pages.flatMap((page) => page.items) ?? []).filter(
		(media) => !existingIds.has(media.id),
	);

	return (
		<Modal
			opened={opened}
			onClose={onClose}
			title={t("collections.addMediaTitle")}
			size="lg"
			centered
		>
			<TVModalAutoFocus
				focusKey={
					items.length > 0 ? `add-media-${items[0].id}` : "add-media-none"
				}
			/>
			<Stack gap="md">
				<TextInput
					placeholder={t("collections.searchMedia")}
					aria-label={t("collections.searchMedia")}
					value={query}
					onChange={(event) => setQuery(event.currentTarget.value)}
				/>
				{list.isPending ? (
					<Text size="sm" c="dimmed">
						{t("common.loading")}
					</Text>
				) : list.isError && items.length === 0 ? (
					<Alert color="red" variant="light" title={t("collections.loadError")}>
						<Button
							variant="light"
							size="xs"
							mt="xs"
							onClick={() => void list.refetch()}
						>
							{t("common.retry")}
						</Button>
					</Alert>
				) : items.length === 0 ? (
					<Text size="sm" c="dimmed">
						{t("collections.noMedia")}
					</Text>
				) : (
					<Stack gap="xs">
						{items.map((media) => (
							<Group
								key={media.id}
								justify="space-between"
								wrap="nowrap"
								gap="sm"
							>
								<Text size="sm" truncate>
									{media.title}
								</Text>
								<TVButton
									focusKey={`add-media-${media.id}`}
									size="xs"
									variant="light"
									leftSection={<Plus size={14} />}
									loading={add.isPending}
									onClick={() => {
										add.mutate(
											{ collectionId, mediaId: media.id },
											{ onError: notifyError },
										);
									}}
								>
									{t("collections.add")}
								</TVButton>
							</Group>
						))}
						{list.isFetchNextPageError ? (
							<Alert
								color="red"
								variant="light"
								title={t("collections.loadError")}
							>
								<Button
									variant="light"
									size="xs"
									mt="xs"
									onClick={() => void list.fetchNextPage()}
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
									onClick={() => void list.fetchNextPage()}
								>
									{t("collections.showMore")}
								</Button>
							)
						)}
					</Stack>
				)}
			</Stack>
		</Modal>
	);
}

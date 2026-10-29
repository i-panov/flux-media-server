import {
	Alert,
	Button,
	Group,
	Modal,
	Stack,
	Text,
	TextInput,
} from "@mantine/core";
import { useQuery } from "@tanstack/react-query";
import { Plus } from "lucide-react";
import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { apiFetch } from "../../api/client";
import { useAddToCollection } from "../../api/collections";
import type { MediaType } from "../../core/media";
import { fetchMediaList } from "../../core/media";
import { useCollectionError } from "./useCollectionError";

const SEARCH_DEBOUNCE_MS = 300;

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
	const [debounced, setDebounced] = useState("");
	const add = useAddToCollection();
	const notifyError = useCollectionError();

	useEffect(() => {
		const timer = setTimeout(
			() => setDebounced(query.trim()),
			SEARCH_DEBOUNCE_MS,
		);
		return () => clearTimeout(timer);
	}, [query]);

	const list = useQuery({
		queryKey: ["media", "picker", type, debounced],
		queryFn: ({ signal }) =>
			fetchMediaList(apiFetch, {
				type,
				q: debounced,
				limit: 50,
				offset: 0,
				signal,
			}),
		retry: false,
		refetchOnWindowFocus: false,
		enabled: opened,
	});

	const items = (list.data?.items ?? []).filter(
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
				) : list.isError ? (
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
								<Button
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
								</Button>
							</Group>
						))}
					</Stack>
				)}
			</Stack>
		</Modal>
	);
}

import {
	Alert,
	Button,
	Group,
	Modal,
	SimpleGrid,
	Skeleton,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { useNavigate, useParams } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	useCollectionItems,
	useCollections,
	useDeleteCollection,
	useRemoveFromCollection,
} from "../../api/collections";
import { isMediaType } from "../../components/mediaType";
import type { MediaType } from "../../core/media";
import { AddMediaToCollectionModal } from "./AddMediaToCollectionModal";
import { CollectionCard } from "./CollectionCard";
import { CollectionFallback } from "./CollectionFallback";
import { CollectionHeader } from "./CollectionHeader";
import { CollectionTile } from "./CollectionTile";
import { descendantIds, TYPE_PATH } from "./collectionUtils";
import { MoveCollectionModal } from "./MoveCollectionModal";
import { MoveToCollectionModal } from "./MoveToCollectionModal";
import { RenameCollectionModal } from "./RenameCollectionModal";
import { useCollectionError } from "./useCollectionError";

export function CollectionDetailPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { id } = useParams({ from: "/collections/$id" });
	const collectionId = Number(id);
	const valid = Number.isInteger(collectionId) && collectionId > 0;
	const collections = useCollections();
	const items = useCollectionItems(collectionId, valid);
	const remove = useRemoveFromCollection();
	const removeCollection = useDeleteCollection();
	const notifyError = useCollectionError();
	const [renameOpened, setRenameOpened] = useState(false);
	const [deleteOpened, setDeleteOpened] = useState(false);
	const [addOpened, setAddOpened] = useState(false);
	const [moveOpened, setMoveOpened] = useState(false);
	const [moveMediaId, setMoveMediaId] = useState<number | null>(null);

	const collection = (collections.data ?? []).find(
		(item) => item.id === collectionId,
	);
	const type: MediaType | null =
		collection !== undefined && isMediaType(collection.type)
			? collection.type
			: null;
	const backPath = type === null ? "/video" : TYPE_PATH[type];

	if (!valid) {
		return (
			<CollectionFallback
				title={t("collections.notFound")}
				backPath={backPath}
			/>
		);
	}

	if (collections.isError) {
		return (
			<CollectionFallback
				title={t("collections.loadError")}
				backPath={backPath}
				onRetry={() => void collections.refetch()}
			/>
		);
	}

	if (collections.isPending) {
		return (
			<Stack gap="md">
				<Skeleton height={32} width="40%" radius="sm" />
				<Skeleton height={240} radius="md" />
			</Stack>
		);
	}

	if (collection === undefined || type === null) {
		return (
			<CollectionFallback
				title={t("collections.notFound")}
				backPath={backPath}
			/>
		);
	}

	const mediaItems = items.data ?? [];
	const children = (collections.data ?? []).filter(
		(child) => child.parent_id === collectionId,
	);
	// Переезд под себя или потомков замкнул бы цикл: исключаем всё поддерево.
	const moveExcluded = descendantIds(collections.data ?? [], collectionId);
	const parent =
		collection.parent_id !== null && collection.parent_id !== undefined
			? (collections.data ?? []).find(
					(item) => item.id === collection.parent_id,
				)
			: undefined;

	return (
		<Stack gap="lg">
			<CollectionHeader
				collection={collection}
				type={type}
				count={mediaItems.length}
				backPath={backPath}
				parent={parent}
				onAdd={() => setAddOpened(true)}
				onRename={() => setRenameOpened(true)}
				onMove={() => setMoveOpened(true)}
				onDelete={() => setDeleteOpened(true)}
			/>

			{children.length > 0 && (
				<Stack gap="sm">
					<Title order={2} size="h4">
						{t("collections.children")}
					</Title>
					<SimpleGrid
						cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }}
						spacing="md"
					>
						{children.map((child) => (
							<CollectionTile key={child.id} collection={child} />
						))}
					</SimpleGrid>
				</Stack>
			)}

			{items.isPending ? (
				<Skeleton height={240} radius="md" />
			) : items.isError ? (
				<Alert color="red" variant="light" title={t("collections.loadError")}>
					<Button
						variant="light"
						size="xs"
						mt="xs"
						onClick={() => void items.refetch()}
					>
						{t("common.retry")}
					</Button>
				</Alert>
			) : mediaItems.length === 0 ? (
				<Alert color="gray" variant="light">
					{t("collections.emptyItems")}
				</Alert>
			) : (
				<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }} spacing="md">
					{mediaItems.map((media) => (
						<CollectionCard
							key={media.id}
							media={media}
							type={type}
							onRemove={() => {
								remove.mutate(
									{ collectionId, mediaId: media.id },
									{ onError: notifyError },
								);
							}}
							onMove={() => setMoveMediaId(media.id)}
						/>
					))}
				</SimpleGrid>
			)}

			<RenameCollectionModal
				key={`${collection.id}-${renameOpened}`}
				collection={collection}
				opened={renameOpened}
				onClose={() => setRenameOpened(false)}
			/>
			<AddMediaToCollectionModal
				opened={addOpened}
				collectionId={collectionId}
				type={type}
				existingIds={new Set(mediaItems.map((media) => media.id))}
				onClose={() => setAddOpened(false)}
			/>
			{moveMediaId !== null && (
				<MoveToCollectionModal
					opened
					sourceId={collectionId}
					mediaId={moveMediaId}
					type={type}
					onClose={() => setMoveMediaId(null)}
				/>
			)}
			{moveOpened && (
				<MoveCollectionModal
					opened
					sourceId={collectionId}
					type={type}
					excludeIds={moveExcluded}
					onMoved={() => {
						setMoveOpened(false);
						void navigate({ to: backPath });
					}}
					onClose={() => setMoveOpened(false)}
				/>
			)}
			<Modal
				opened={deleteOpened}
				onClose={() => setDeleteOpened(false)}
				title={t("collections.deleteTitle")}
				centered
			>
				<Stack gap="md">
					<Text size="sm">{t("collections.deleteConfirm")}</Text>
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setDeleteOpened(false)}>
							{t("collections.cancel")}
						</Button>
						<Button
							color="red"
							loading={removeCollection.isPending}
							onClick={() => {
								removeCollection.mutate(collection.id, {
									onSuccess: () => {
										void navigate({ to: backPath });
									},
									onError: notifyError,
								});
							}}
						>
							{t("collections.delete")}
						</Button>
					</Group>
				</Stack>
			</Modal>
		</Stack>
	);
}

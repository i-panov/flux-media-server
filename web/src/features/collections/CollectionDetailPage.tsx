import {
	Alert,
	Button,
	SimpleGrid,
	Skeleton,
	Stack,
	Title,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useNavigate, useParams } from "@tanstack/react-router";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	useCollectionItems,
	useCollections,
	useRemoveFromCollection,
} from "../../api/collections";
import { isMediaType } from "../../components/mediaType";
import type { Media, MediaType } from "../../core/media";
import { TVFocusScope, useTVFocusable } from "../tv/tvFocus";
import { useTVMode } from "../tv/useTVMode";
import { AddMediaToCollectionModal } from "./AddMediaToCollectionModal";
import { BulkMoveCollectionModal } from "./BulkMoveCollectionModal";
import { CollectionBulkBar } from "./CollectionBulkBar";
import { CollectionCard } from "./CollectionCard";
import { CollectionFallback } from "./CollectionFallback";
import { CollectionHeader } from "./CollectionHeader";
import { CollectionTile } from "./CollectionTile";
import { descendantIds, TYPE_PATH } from "./collectionUtils";
import { DeleteCollectionModal } from "./DeleteCollectionModal";
import { MoveCollectionModal } from "./MoveCollectionModal";
import { MoveToCollectionModal } from "./MoveToCollectionModal";
import { RenameCollectionModal } from "./RenameCollectionModal";
import { useCollectionError } from "./useCollectionError";
import { useCollectionSelection } from "./useCollectionSelection";

function CollectionMediaGrid({
	items,
	type,
	isPending,
	isError,
	onRetry,
	onRemove,
	onMove,
	selected,
	onToggle,
	readOnly,
}: {
	items: Media[];
	type: MediaType;
	isPending: boolean;
	isError: boolean;
	onRetry: () => void;
	onRemove: (mediaId: number) => void;
	onMove: (mediaId: number) => void;
	selected: ReadonlySet<number>;
	onToggle: (mediaId: number) => void;
	readOnly: boolean;
}) {
	const { t } = useTranslation();
	if (isPending) {
		return <Skeleton height={240} radius="md" />;
	}
	if (isError) {
		return (
			<Alert color="red" variant="light" title={t("collections.loadError")}>
				<Button variant="light" size="xs" mt="xs" onClick={onRetry}>
					{t("common.retry")}
				</Button>
			</Alert>
		);
	}
	if (items.length === 0) {
		return (
			<Alert color="gray" variant="light">
				{t("collections.emptyItems")}
			</Alert>
		);
	}
	return (
		<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }} spacing="md">
			{items.map((media) => (
				<CollectionCard
					key={media.id}
					media={media}
					type={type}
					onRemove={() => onRemove(media.id)}
					onMove={() => onMove(media.id)}
					selected={selected.has(media.id)}
					onToggle={() => onToggle(media.id)}
					readOnly={readOnly}
				/>
			))}
		</SimpleGrid>
	);
}

function toggleSelected(
	prev: ReadonlySet<number>,
	mediaId: number,
): Set<number> {
	const next = new Set(prev);
	if (next.has(mediaId)) {
		next.delete(mediaId);
	} else {
		next.add(mediaId);
	}
	return next;
}

// eslint-disable-next-line max-lines-per-function -- страница держит хуки и проводку модалок вместе.
export function CollectionDetailPage() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const { id } = useParams({ from: "/collections/$id" });
	const collectionId = Number(id);
	const valid = Number.isInteger(collectionId) && collectionId > 0;
	const collections = useCollections();
	const items = useCollectionItems(collectionId, valid);
	const remove = useRemoveFromCollection();
	const notifyError = useCollectionError();
	const [renameOpened, setRenameOpened] = useState(false);
	const [deleteOpened, setDeleteOpened] = useState(false);
	const [addOpened, setAddOpened] = useState(false);
	const [moveOpened, setMoveOpened] = useState(false);
	const [moveMediaId, setMoveMediaId] = useState<number | null>(null);
	const { selectedIds, setSelectedIds, bulkMoveOpened, setBulkMoveOpened } =
		useCollectionSelection(collectionId);
	const { targetRef: tvRef, tvMode } =
		useTVFocusable<HTMLDivElement>("collection-detail");
	// CRUD коллекций — отдельная capability: в ТВ-профиле остаётся только
	// просмотр, а не «выключено всё из-за tvMode».
	const { capabilities } = useTVMode();
	const canManageCollections = capabilities.canManageCollections;
	const { targetRef: tvLoadingRef } = useTVFocusable<HTMLDivElement>(
		"collection-detail-loading",
	);

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
			<Stack gap="md" ref={tvLoadingRef} tabIndex={tvMode ? -1 : undefined}>
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
	const moveExcluded = descendantIds(collections.data ?? [], collectionId);
	const parent =
		collection.parent_id !== null && collection.parent_id !== undefined
			? (collections.data ?? []).find(
					(item) => item.id === collection.parent_id,
				)
			: undefined;

	return (
		<Stack
			gap="lg"
			ref={tvRef}
			tabIndex={tvMode ? -1 : undefined}
			data-tv-page-root="true"
			data-tv-focus-key="collection-detail"
		>
			<TVFocusScope focusKey="collection-detail">
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
					readOnly={!canManageCollections}
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

				{canManageCollections && (
					<CollectionBulkBar
						collectionId={collectionId}
						selectedIds={selectedIds}
						onMove={() => setBulkMoveOpened(true)}
						onClear={() => setSelectedIds(new Set())}
					/>
				)}
				<CollectionMediaGrid
					items={mediaItems}
					type={type}
					isPending={items.isPending}
					isError={items.isError}
					onRetry={() => void items.refetch()}
					onRemove={(mediaId) => {
						setSelectedIds((prev) => {
							const next = new Set(prev);
							next.delete(mediaId);
							return next;
						});
						remove.mutate({ collectionId, mediaId }, { onError: notifyError });
					}}
					onMove={(mediaId) => setMoveMediaId(mediaId)}
					selected={selectedIds}
					onToggle={(mediaId) =>
						setSelectedIds((prev) => toggleSelected(prev, mediaId))
					}
					readOnly={!canManageCollections}
				/>
			</TVFocusScope>

			{canManageCollections && (
				<>
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
					{bulkMoveOpened && (
						<BulkMoveCollectionModal
							opened
							sourceId={collectionId}
							type={type}
							mediaIds={[...selectedIds]}
							onClose={() => setBulkMoveOpened(false)}
							onMoved={(result) => {
								setBulkMoveOpened(false);
								setSelectedIds(new Set());
								if (result.skipped.length > 0) {
									notifications.show({
										color: "yellow",
										message: t("collections.bulkSkipped", {
											count: result.skipped.length,
										}),
									});
								}
							}}
						/>
					)}
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
					<DeleteCollectionModal
						collectionId={collectionId}
						opened={deleteOpened}
						backPath={backPath}
						onClose={() => setDeleteOpened(false)}
					/>
				</>
			)}
		</Stack>
	);
}

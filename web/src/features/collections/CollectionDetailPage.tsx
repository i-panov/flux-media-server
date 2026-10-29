import {
	ActionIcon,
	Alert,
	Badge,
	Button,
	Group,
	Menu,
	Modal,
	SimpleGrid,
	Skeleton,
	Stack,
	Text,
	TextInput,
	Title,
	Tooltip,
} from "@mantine/core";
import { useNavigate, useParams } from "@tanstack/react-router";
import { ArrowLeft, MoreVertical, Pencil, Plus, Trash2, X } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	type Collection,
	useCollectionItems,
	useCollections,
	useDeleteCollection,
	useRemoveFromCollection,
	useRenameCollection,
} from "../../api/collections";
import type { Media, MediaType } from "../../core/media";
import { AudioCard } from "../audio/AudioCard";
import { MemeCard } from "../memes/MemeCard";
import { VideoCard } from "../video/VideoCard";
import { AddMediaToCollectionModal } from "./AddMediaToCollectionModal";
import { CollectionTile } from "./CollectionTile";
import { useCollectionError } from "./useCollectionError";

const TYPE_LABEL_KEYS: Record<MediaType, string> = {
	video: "media.video",
	audio: "media.audio",
	image: "media.memes",
};

const TYPE_PATH: Record<MediaType, "/video" | "/audio" | "/memes"> = {
	video: "/video",
	audio: "/audio",
	image: "/memes",
};

const BACK_LABEL_KEY = "collections.back";

function CollectionHeader({
	collection,
	type,
	count,
	backPath,
	parent,
	onAdd,
	onRename,
	onDelete,
}: {
	collection: Collection;
	type: MediaType;
	count: number;
	backPath: "/video" | "/audio" | "/memes";
	parent?: Collection;
	onAdd: () => void;
	onRename: () => void;
	onDelete: () => void;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const backLabel =
		parent === undefined
			? t(BACK_LABEL_KEY)
			: t("collections.backToParent", { name: parent.name });
	return (
		<Stack gap="xs">
			<Group justify="space-between" align="center" wrap="wrap">
				<Button
					variant="subtle"
					leftSection={<ArrowLeft size={16} />}
					onClick={() => {
						if (parent === undefined) {
							void navigate({ to: backPath });
						} else {
							void navigate({
								to: "/collections/$id",
								params: { id: String(parent.id) },
							});
						}
					}}
				>
					{backLabel}
				</Button>
				<Group gap="xs">
					<Button
						variant="light"
						leftSection={<Plus size={16} />}
						onClick={onAdd}
					>
						{t("collections.addMedia")}
					</Button>
					<Menu position="bottom-end" withinPortal>
						<Menu.Target>
							<ActionIcon
								variant="default"
								size="lg"
								aria-label={t("collections.actions")}
							>
								<MoreVertical size={18} />
							</ActionIcon>
						</Menu.Target>
						<Menu.Dropdown>
							<Menu.Item leftSection={<Pencil size={14} />} onClick={onRename}>
								{t("collections.rename")}
							</Menu.Item>
							<Menu.Item
								color="red"
								leftSection={<Trash2 size={14} />}
								onClick={onDelete}
							>
								{t("collections.delete")}
							</Menu.Item>
						</Menu.Dropdown>
					</Menu>
				</Group>
			</Group>
			<Group gap="sm" wrap="wrap">
				<Title order={1} size="h2">
					{collection.name}
				</Title>
				<Badge variant="light" color="violet">
					{t(TYPE_LABEL_KEYS[type])}
				</Badge>
			</Group>
			<Text size="sm" c="dimmed">
				{t("collections.itemsCount", { count })}
			</Text>
		</Stack>
	);
}

function isMediaType(value: string): value is MediaType {
	return value === "video" || value === "audio" || value === "image";
}

function CollectionCard({
	media,
	type,
	onRemove,
}: {
	media: Media;
	type: MediaType;
	onRemove: () => void;
}) {
	const { t } = useTranslation();
	return (
		<div className="relative">
			{type === "video" ? (
				<VideoCard media={media} />
			) : type === "audio" ? (
				<AudioCard media={media} />
			) : (
				<MemeCard media={media} />
			)}
			<Tooltip label={t("collections.removeItem")} withArrow>
				<ActionIcon
					variant="filled"
					color="red"
					size="lg"
					radius="xl"
					aria-label={t("collections.removeItem")}
					className="absolute bottom-2 left-2 z-10"
					onClick={onRemove}
				>
					<X size={18} />
				</ActionIcon>
			</Tooltip>
		</div>
	);
}

function RenameCollectionModal({
	collection,
	opened,
	onClose,
}: {
	collection: Collection;
	opened: boolean;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const [name, setName] = useState(collection.name);
	const rename = useRenameCollection();
	const notifyError = useCollectionError();
	return (
		<Modal
			opened={opened}
			onClose={onClose}
			title={t("collections.renameTitle")}
			centered
		>
			<Stack gap="md">
				<TextInput
					label={t("collections.name")}
					value={name}
					data-autofocus
					onChange={(event) => setName(event.currentTarget.value)}
				/>
				<Group justify="flex-end">
					<Button variant="default" onClick={onClose}>
						{t("collections.cancel")}
					</Button>
					<Button
						loading={rename.isPending}
						disabled={name.trim() === ""}
						onClick={() => {
							rename.mutate(
								{ id: collection.id, name: name.trim() },
								{ onSuccess: onClose, onError: notifyError },
							);
						}}
					>
						{t("collections.save")}
					</Button>
				</Group>
			</Stack>
		</Modal>
	);
}

function CollectionFallback({
	title,
	onRetry,
}: {
	title: string;
	onRetry?: () => void;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	return (
		<Stack gap="md">
			<Alert color="red" variant="light" title={title}>
				{onRetry !== undefined && (
					<Button variant="light" size="xs" mt="xs" onClick={onRetry}>
						{t("common.retry")}
					</Button>
				)}
			</Alert>
			<Button
				variant="light"
				w="fit-content"
				onClick={() => void navigate({ to: "/video" })}
			>
				{t(BACK_LABEL_KEY)}
			</Button>
		</Stack>
	);
}

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

	const collection = (collections.data ?? []).find(
		(item) => item.id === collectionId,
	);
	const type: MediaType | null =
		collection !== undefined && isMediaType(collection.type)
			? collection.type
			: null;
	const backPath = type === null ? "/video" : TYPE_PATH[type];

	if (!valid) {
		return <CollectionFallback title={t("collections.notFound")} />;
	}

	if (collections.isError) {
		return (
			<CollectionFallback
				title={t("collections.loadError")}
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
		return <CollectionFallback title={t("collections.notFound")} />;
	}

	const mediaItems = items.data ?? [];
	const children = (collections.data ?? []).filter(
		(child) => child.parent_id === collectionId,
	);
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

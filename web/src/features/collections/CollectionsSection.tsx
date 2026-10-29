import {
	ActionIcon,
	Alert,
	Button,
	Card,
	Group,
	SimpleGrid,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { Folder, FolderPlus, Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { type Collection, useCollections } from "../../api/collections";
import type { MediaType } from "../../core/media";
import { CollectionTile } from "./CollectionTile";
import { CreateCollectionModal } from "./CreateCollectionModal";

function rootCollections(
	collections: Collection[],
	type: MediaType,
): Collection[] {
	const ids = new Set(collections.map((collection) => collection.id));
	return collections.filter(
		(collection) =>
			collection.type === type &&
			(collection.parent_id === null ||
				collection.parent_id === undefined ||
				!ids.has(collection.parent_id)),
	);
}

export function CollectionsSection({ type }: { type: MediaType }) {
	const { t } = useTranslation();
	const [createOpened, setCreateOpened] = useState(false);
	const collections = useCollections();
	const roots = rootCollections(collections.data ?? [], type);
	if (collections.isPending) {
		return null;
	}
	return (
		<Stack gap="sm">
			<Group justify="space-between" align="center">
				<Group gap="xs">
					<Folder size={18} className="text-[var(--mantine-color-violet-5)]" />
					<Title order={2} size="h3">
						{t("collections.title")}
					</Title>
				</Group>
				<ActionIcon
					variant="light"
					aria-label={t("collections.create")}
					title={t("collections.create")}
					onClick={() => setCreateOpened(true)}
				>
					<Plus size={18} />
				</ActionIcon>
			</Group>
			{collections.isError ? (
				<Alert color="red" variant="light" title={t("collections.loadError")}>
					<Button
						variant="light"
						size="xs"
						mt="xs"
						onClick={() => void collections.refetch()}
					>
						{t("common.retry")}
					</Button>
				</Alert>
			) : roots.length === 0 ? (
				<Card withBorder padding="md" radius="md">
					<Group gap="sm">
						<FolderPlus
							size={20}
							className="text-[var(--mantine-color-dimmed)]"
						/>
						<Text size="sm" c="dimmed">
							{t("collections.empty")}
						</Text>
					</Group>
				</Card>
			) : (
				<SimpleGrid cols={{ base: 2, sm: 3, md: 4, lg: 5, xl: 6 }} spacing="md">
					{roots.map((collection) => (
						<CollectionTile key={collection.id} collection={collection} />
					))}
				</SimpleGrid>
			)}
			<CreateCollectionModal
				opened={createOpened}
				type={type}
				onClose={() => setCreateOpened(false)}
			/>
		</Stack>
	);
}

import {
	Alert,
	Button,
	Group,
	Loader,
	Modal,
	Stack,
	Text,
} from "@mantine/core";
import { FolderPlus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useAddToCollection, useCollections } from "../../api/collections";
import type { MediaType } from "../../core/media";
import { TVButton, TVModalAutoFocus } from "../tv/tvFocus";
import { CreateCollectionModal } from "./CreateCollectionModal";
import { useCollectionError } from "./useCollectionError";

export function AddToCollectionModal({
	opened,
	mediaId,
	type,
	onClose,
}: {
	opened: boolean;
	mediaId: number;
	type: MediaType;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const collections = useCollections();
	const add = useAddToCollection();
	const notifyError = useCollectionError();
	const [createOpened, setCreateOpened] = useState(false);

	const matching = (collections.data ?? []).filter(
		(collection) => collection.type === type,
	);

	return (
		<>
			<Modal
				opened={opened}
				onClose={onClose}
				title={t("collections.addTitle")}
				centered
			>
				<TVModalAutoFocus focusKey="add-to-collection-cancel" />
				<Stack gap="sm">
					{collections.isPending ? (
						<Group justify="center" py="md">
							<Loader size="sm" aria-label={t("common.loading")} />
						</Group>
					) : collections.isError ? (
						<Alert
							color="red"
							variant="light"
							title={t("collections.loadError")}
						>
							<Button
								variant="light"
								size="xs"
								mt="xs"
								onClick={() => void collections.refetch()}
							>
								{t("common.retry")}
							</Button>
						</Alert>
					) : matching.length === 0 ? (
						<Text size="sm" c="dimmed">
							{t("collections.emptyForType")}
						</Text>
					) : (
						matching.map((collection) => (
							<TVButton
								key={collection.id}
								focusKey={`add-to-collection-${collection.id}`}
								variant="light"
								justify="flex-start"
								leftSection={<FolderPlus size={16} />}
								loading={add.isPending}
								onClick={() => {
									add.mutate(
										{ collectionId: collection.id, mediaId },
										{ onSuccess: onClose, onError: notifyError },
									);
								}}
							>
								{collection.name}
							</TVButton>
						))
					)}
					<Group justify="flex-end">
						<TVButton
							focusKey="add-to-collection-cancel"
							variant="default"
							onClick={onClose}
						>
							{t("collections.cancel")}
						</TVButton>
						<TVButton
							focusKey="add-to-collection-create"
							variant="light"
							leftSection={<FolderPlus size={16} />}
							onClick={() => setCreateOpened(true)}
						>
							{t("collections.create")}
						</TVButton>
					</Group>
					{add.isError && (
						<Text size="sm" c="red">
							{t("collections.addError")}
						</Text>
					)}
				</Stack>
			</Modal>
			<CreateCollectionModal
				opened={createOpened}
				type={type}
				onClose={() => setCreateOpened(false)}
			/>
		</>
	);
}

import { Alert, Button, Group, Modal, Stack, Text } from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCollections, useMoveCollection } from "../../api/collections";
import type { MediaType } from "../../core/media";
import { TVButton, TVModalAutoFocus } from "../tv/tvFocus";
import { CollectionPickList } from "./CollectionPickList";
import { CreateCollectionModal } from "./CreateCollectionModal";
import { useCollectionError } from "./useCollectionError";

// Перенос коллекции под другого родителя или в корень (как во Flutter).
// После успеха шапка экрана устаревает (имя/родитель старые), поэтому
// вызывающий уводит назад к списку, как maybePop во Flutter.
export function MoveCollectionModal({
	opened,
	sourceId,
	type,
	excludeIds,
	onMoved,
	onClose,
}: {
	opened: boolean;
	sourceId: number;
	type: MediaType;
	excludeIds: ReadonlySet<number>;
	onMoved: () => void;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const collections = useCollections();
	const move = useMoveCollection();
	const notifyError = useCollectionError();
	const [createOpened, setCreateOpened] = useState(false);

	return (
		<>
			<Modal
				opened={opened}
				onClose={onClose}
				title={t("collections.moveCollectionTitle")}
				centered
			>
				<TVModalAutoFocus focusKey="move-collection-cancel" />
				<Stack gap="sm">
					{collections.isError ? (
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
					) : (
						<CollectionPickList
							type={type}
							collections={collections.data ?? []}
							excludeIds={excludeIds}
							allowRoot
							pending={move.isPending}
							loading={collections.isPending}
							onPick={(parentId) => {
								move.mutate(
									{ id: sourceId, parentId },
									{ onSuccess: onMoved, onError: notifyError },
								);
							}}
						/>
					)}
					<Group justify="flex-end">
						<TVButton
							focusKey="move-collection-cancel"
							variant="default"
							onClick={onClose}
						>
							{t("collections.cancel")}
						</TVButton>
						<TVButton
							focusKey="move-collection-create"
							variant="light"
							onClick={() => setCreateOpened(true)}
						>
							{t("collections.create")}
						</TVButton>
					</Group>
					{move.isError && (
						<Text size="sm" c="red">
							{t("collections.moveCollectionError")}
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

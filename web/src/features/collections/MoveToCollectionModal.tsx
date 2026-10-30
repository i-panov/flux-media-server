import { Alert, Button, Group, Modal, Stack, Text } from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCollections, useMoveCollectionItem } from "../../api/collections";
import type { MediaType } from "../../core/media";
import { CollectionPickList } from "./CollectionPickList";
import { CreateCollectionModal } from "./CreateCollectionModal";
import { useCollectionError } from "./useCollectionError";

// Перенос элемента в другую коллекцию того же типа (как во Flutter):
// текущая исключена из списка, сервер additionally проверяет тип (400)
// и дубликат (409). Новую коллекцию можно создать прямо отсюда.
export function MoveToCollectionModal({
	opened,
	sourceId,
	mediaId,
	type,
	onClose,
}: {
	opened: boolean;
	sourceId: number;
	mediaId: number;
	type: MediaType;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const collections = useCollections();
	const move = useMoveCollectionItem();
	const notifyError = useCollectionError();
	const [createOpened, setCreateOpened] = useState(false);

	return (
		<>
			<Modal
				opened={opened}
				onClose={onClose}
				title={t("collections.moveTitle")}
				centered
			>
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
							excludeIds={new Set([sourceId])}
							allowRoot={false}
							pending={move.isPending}
							loading={collections.isPending}
							onPick={(toCollectionId) => {
								if (toCollectionId === null) {
									return;
								}
								move.mutate(
									{
										sourceId,
										toCollectionId,
										mediaId,
									},
									{ onSuccess: onClose, onError: notifyError },
								);
							}}
						/>
					)}
					<Group justify="flex-end">
						<Button variant="default" onClick={onClose}>
							{t("collections.cancel")}
						</Button>
						<Button variant="light" onClick={() => setCreateOpened(true)}>
							{t("collections.create")}
						</Button>
					</Group>
					{move.isError && (
						<Text size="sm" c="red">
							{t("collections.moveError")}
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

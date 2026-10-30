import { Alert, Button, Group, Modal, Stack, Text } from "@mantine/core";
import { FolderInput } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCollections, useMoveCollectionItem } from "../../api/collections";
import type { MediaType } from "../../core/media";
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

	const matching = (collections.data ?? []).filter(
		(collection) => collection.type === type && collection.id !== sourceId,
	);

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
					) : matching.length === 0 ? (
						<Text size="sm" c="dimmed">
							{t("collections.emptyForMove")}
						</Text>
					) : (
						matching.map((collection) => (
							<Button
								key={collection.id}
								variant="light"
								justify="flex-start"
								leftSection={<FolderInput size={16} />}
								loading={move.isPending}
								onClick={() => {
									move.mutate(
										{
											sourceId,
											toCollectionId: collection.id,
											mediaId,
										},
										{ onSuccess: onClose, onError: notifyError },
									);
								}}
							>
								{collection.name}
							</Button>
						))
					)}
					<Group justify="flex-end">
						<Button variant="default" onClick={onClose}>
							{t("collections.cancel")}
						</Button>
						<Button
							variant="light"
							leftSection={<FolderInput size={16} />}
							onClick={() => setCreateOpened(true)}
						>
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

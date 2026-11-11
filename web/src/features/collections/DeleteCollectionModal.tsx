import { Group, Modal, Stack, Text } from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { useCollectionStats, useDeleteCollection } from "../../api/collections";
import { TVButton, TVModalAutoFocus } from "../tv/tvFocus";
import { useCollectionError } from "./useCollectionError";

export function DeleteCollectionModal({
	collectionId,
	opened,
	backPath,
	onClose,
}: {
	collectionId: number;
	opened: boolean;
	backPath: string;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const stats = useCollectionStats(collectionId, opened);
	const remove = useDeleteCollection();
	const notifyError = useCollectionError();

	return (
		<Modal
			opened={opened}
			onClose={onClose}
			title={t("collections.deleteTitle")}
			centered
		>
			<TVModalAutoFocus focusKey="delete-collection-cancel" />
			<Stack gap="md">
				<Text size="sm">{t("collections.deleteConfirm")}</Text>
				{stats.data !== undefined && (
					<Text size="sm" c="dimmed">
						{t("collections.deleteStats", {
							subcollections: stats.data.subcollections,
							items: stats.data.items,
						})}
					</Text>
				)}
				<Group justify="flex-end">
					<TVButton
						focusKey="delete-collection-cancel"
						variant="default"
						onClick={onClose}
					>
						{t("collections.cancel")}
					</TVButton>
					<TVButton
						focusKey="delete-collection-confirm"
						color="red"
						loading={remove.isPending}
						onClick={() => {
							remove.mutate(collectionId, {
								onSuccess: () => {
									onClose();
									void navigate({ to: backPath });
								},
								onError: notifyError,
							});
						}}
					>
						{t("collections.delete")}
					</TVButton>
				</Group>
			</Stack>
		</Modal>
	);
}

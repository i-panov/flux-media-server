import { Alert, Button, Group, Modal, Stack } from "@mantine/core";
import { useTranslation } from "react-i18next";
import {
	useBulkMoveCollectionItems,
	useCollections,
} from "../../api/collections";
import type { MediaType } from "../../core/media";
import { TVButton, TVModalAutoFocus } from "../tv/tvFocus";
import { CollectionPickList } from "./CollectionPickList";
import { useCollectionError } from "./useCollectionError";

export function BulkMoveCollectionModal({
	opened,
	sourceId,
	type,
	mediaIds,
	onClose,
	onMoved,
}: {
	opened: boolean;
	sourceId: number;
	type: MediaType;
	mediaIds: number[];
	onClose: () => void;
	onMoved: (result: { moved: number[]; skipped: number[] }) => void;
}) {
	const { t } = useTranslation();
	const collections = useCollections();
	const move = useBulkMoveCollectionItems(sourceId);
	const notifyError = useCollectionError();

	return (
		<Modal
			opened={opened}
			onClose={onClose}
			title={t("collections.moveTitle")}
			centered
		>
			<TVModalAutoFocus focusKey="bulk-move-cancel" />
			<Stack gap="sm">
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
								{ mediaIds, toCollectionId },
								{
									onSuccess: (result) =>
										onMoved({
											moved: result.moved ?? [],
											skipped: result.skipped ?? [],
										}),
									onError: notifyError,
								},
							);
						}}
					/>
				)}
				<Group justify="flex-end">
					<TVButton
						focusKey="bulk-move-cancel"
						variant="default"
						onClick={onClose}
					>
						{t("collections.cancel")}
					</TVButton>
				</Group>
			</Stack>
		</Modal>
	);
}

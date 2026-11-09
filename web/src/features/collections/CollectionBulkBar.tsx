import { Button, Group, Text } from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useTranslation } from "react-i18next";
import { useBulkRemoveCollectionItems } from "../../api/collections";
import { clickNode, useTVFocusable } from "../tv/tvFocus";
import { useCollectionError } from "./useCollectionError";

export function CollectionBulkBar({
	collectionId,
	selectedIds,
	onMove,
	onClear,
}: {
	collectionId: number;
	selectedIds: ReadonlySet<number>;
	onMove: () => void;
	onClear: () => void;
}) {
	const { t } = useTranslation();
	const remove = useBulkRemoveCollectionItems(collectionId);
	const notifyError = useCollectionError();
	const { targetRef: removeRef } = useTVFocusable<HTMLButtonElement>(
		"bulk-remove",
		clickNode,
	);
	const { targetRef: moveRef } = useTVFocusable<HTMLButtonElement>(
		"bulk-move",
		clickNode,
	);
	const { targetRef: clearRef } = useTVFocusable<HTMLButtonElement>(
		"bulk-clear",
		clickNode,
	);
	if (selectedIds.size === 0) {
		return null;
	}
	return (
		<Group gap="xs" wrap="wrap">
			<Text size="sm" fw={600}>
				{t("collections.selected", { count: selectedIds.size })}
			</Text>
			<Button
				variant="light"
				color="red"
				size="xs"
				loading={remove.isPending}
				ref={removeRef}
				onClick={() => {
					remove.mutate([...selectedIds], {
						onSuccess: (result) => {
							onClear();
							if ((result.skipped ?? []).length > 0) {
								notifications.show({
									color: "yellow",
									message: t("collections.bulkSkipped", {
										count: (result.skipped ?? []).length,
									}),
								});
							}
						},
						onError: notifyError,
					});
				}}
			>
				{t("collections.removeSelected")}
			</Button>
			<Button
				variant="light"
				size="xs"
				disabled={remove.isPending}
				ref={moveRef}
				onClick={onMove}
			>
				{t("collections.moveSelected")}
			</Button>
			<Button variant="subtle" size="xs" ref={clearRef} onClick={onClear}>
				{t("collections.clearSelection")}
			</Button>
		</Group>
	);
}

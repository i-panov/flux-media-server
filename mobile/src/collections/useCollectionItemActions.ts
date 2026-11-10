import type { BulkResult, Media } from "@flux/shared";
import { router } from "expo-router";
import { Alert } from "react-native";
import {
	useBulkRemoveCollectionItems,
	useRemoveFromCollection,
} from "../api/collections";
import { t } from "../i18n";
import { useAudioActions } from "../player/AudioProvider";
import type { CollectionDialog } from "./dialog";
import type { CollectionSelection } from "./useCollectionSelection";

interface UseCollectionItemActionsInput {
	collectionId: number | null;
	media: readonly Media[];
	selection: CollectionSelection;
	setDialog: (dialog: CollectionDialog) => void;
}

export interface CollectionItemActions {
	onItemPress: (item: Media) => void;
	removeOne: (item: Media) => void;
	moveOne: (mediaId: number) => void;
	confirmBulkRemove: () => void;
	handleMoved: (result: BulkResult) => void;
	handleBulkRemoved: (result: BulkResult) => void;
	bulkPending: boolean;
}

// Действия над элементами коллекции вынесены из экрана: так основной
// компонент остаётся разметкой, а мутации/алерты можно читать отдельно.
export function useCollectionItemActions({
	collectionId,
	media,
	selection,
	setDialog,
}: UseCollectionItemActionsInput): CollectionItemActions {
	const removeItem = useRemoveFromCollection();
	const bulkRemove = useBulkRemoveCollectionItems();
	const { playQueue } = useAudioActions();

	const showError = (message: string) => {
		Alert.alert(t("collections.actionError"), message);
	};

	const playItem = (item: Media) => {
		if (item.type === "audio") {
			const queue = media.filter((entry) => entry.type === "audio");
			const index = queue.findIndex((entry) => entry.id === item.id);
			playQueue(queue, Math.max(index, 0));
			router.push("/player");
			return;
		}
		if (item.type === "video") {
			router.push(`/video/${item.id}`);
		}
	};

	const onItemPress = (item: Media) => {
		if (selection.selecting) {
			selection.toggle(item.id);
			return;
		}
		playItem(item);
	};

	const removeOne = (item: Media) => {
		if (collectionId === null) {
			return;
		}
		Alert.alert(
			t("collections.removeItemTitle"),
			t("collections.removeItemConfirm"),
			[
				{ text: t("common.cancel"), style: "cancel" },
				{
					text: t("collections.removeItem"),
					style: "destructive",
					onPress: () => {
						removeItem.mutate(
							{ collectionId, mediaId: item.id },
							{ onError: () => showError(t("collections.removeError")) },
						);
					},
				},
			],
		);
	};

	const moveOne = (mediaId: number) => {
		setDialog({ kind: "moveItems", mediaIds: [mediaId] });
	};

	const noticeSkipped = (
		result: BulkResult,
		done: number,
		messageKey: "collections.bulkMovePartial" | "collections.bulkRemovePartial",
	) => {
		const skipped = result.skipped?.length ?? 0;
		if (skipped === 0) {
			return;
		}
		const message =
			messageKey === "collections.bulkMovePartial"
				? t(messageKey, { moved: done, skipped })
				: t(messageKey, { removed: done, skipped });
		Alert.alert(t("collections.actionDone"), message);
	};

	const handleMoved = (result: BulkResult) => {
		setDialog(null);
		selection.exit();
		noticeSkipped(
			result,
			result.moved?.length ?? 0,
			"collections.bulkMovePartial",
		);
	};

	const handleBulkRemoved = (result: BulkResult) => {
		selection.exit();
		noticeSkipped(
			result,
			result.removed?.length ?? 0,
			"collections.bulkRemovePartial",
		);
	};

	const confirmBulkRemove = () => {
		if (collectionId === null || selection.selected.size === 0) {
			return;
		}
		const mediaIds = [...selection.selected];
		Alert.alert(
			t("collections.bulkRemoveTitle"),
			t("collections.bulkRemoveConfirm", { count: mediaIds.length }),
			[
				{ text: t("common.cancel"), style: "cancel" },
				{
					text: t("collections.removeSelected"),
					style: "destructive",
					onPress: () => {
						bulkRemove.mutate(
							{ collectionId, mediaIds },
							{
								onSuccess: handleBulkRemoved,
								onError: () => showError(t("collections.removeError")),
							},
						);
					},
				},
			],
		);
	};

	return {
		onItemPress,
		removeOne,
		moveOne,
		confirmBulkRemove,
		handleMoved,
		handleBulkRemoved,
		bulkPending: bulkRemove.isPending,
	};
}

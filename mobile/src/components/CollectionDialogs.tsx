import type { BulkResult, Collection } from "@flux/shared";
import type { CollectionDialog } from "../collections/dialog";
import { asMediaType } from "../collections/tree";
import { CreateCollectionModal } from "./CreateCollectionModal";
import { DeleteCollectionModal } from "./DeleteCollectionModal";
import { MoveCollectionItemsModal } from "./MoveCollectionItemsModal";
import { MoveCollectionModal } from "./MoveCollectionModal";
import { RenameCollectionModal } from "./RenameCollectionModal";

interface CollectionDialogsProps {
	dialog: CollectionDialog;
	collection: Collection;
	collections: readonly Collection[];
	onClose: () => void;
	onMoved: (result: BulkResult) => void;
	onDeleted: () => void;
}

// Все модалки экрана коллекции в одном месте: основной компонент только
// выбирает, какой диалог открыт, и не тащит пять почти одинаковых веток.
export function CollectionDialogs({
	dialog,
	collection,
	collections,
	onClose,
	onMoved,
	onDeleted,
}: CollectionDialogsProps) {
	if (dialog === null) {
		return null;
	}
	switch (dialog.kind) {
		case "create": {
			const type = asMediaType(collection.type);
			if (type === null || type === "image") {
				return null;
			}
			return (
				<CreateCollectionModal
					visible
					fixedType={type}
					parentId={collection.id}
					onClose={onClose}
				/>
			);
		}
		case "rename":
			return (
				<RenameCollectionModal
					visible
					collection={collection}
					onClose={onClose}
				/>
			);
		case "move":
			return (
				<MoveCollectionModal
					visible
					collection={collection}
					collections={collections}
					onClose={onClose}
				/>
			);
		case "delete":
			return (
				<DeleteCollectionModal
					visible
					collection={collection}
					onClose={onClose}
					onDeleted={onDeleted}
				/>
			);
		default:
			return (
				<MoveCollectionItemsModal
					visible
					collection={collection}
					collections={collections}
					mediaIds={dialog.mediaIds}
					onClose={onClose}
					onMoved={onMoved}
				/>
			);
	}
}

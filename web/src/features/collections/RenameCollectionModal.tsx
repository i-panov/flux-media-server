import { Button, Group, Modal, Stack, TextInput } from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { type Collection, useRenameCollection } from "../../api/collections";
import { useCollectionError } from "./useCollectionError";

export function RenameCollectionModal({
	collection,
	opened,
	onClose,
}: {
	collection: Collection;
	opened: boolean;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const [name, setName] = useState(collection.name);
	const rename = useRenameCollection();
	const notifyError = useCollectionError();
	return (
		<Modal
			opened={opened}
			onClose={onClose}
			title={t("collections.renameTitle")}
			centered
		>
			<Stack gap="md">
				<TextInput
					label={t("collections.name")}
					value={name}
					data-autofocus
					onChange={(event) => setName(event.currentTarget.value)}
				/>
				<Group justify="flex-end">
					<Button variant="default" onClick={onClose}>
						{t("collections.cancel")}
					</Button>
					<Button
						loading={rename.isPending}
						disabled={name.trim() === ""}
						onClick={() => {
							rename.mutate(
								{ id: collection.id, name: name.trim() },
								{ onSuccess: onClose, onError: notifyError },
							);
						}}
					>
						{t("collections.save")}
					</Button>
				</Group>
			</Stack>
		</Modal>
	);
}

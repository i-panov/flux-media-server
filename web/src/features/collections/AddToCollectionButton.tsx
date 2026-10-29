import { Button } from "@mantine/core";
import { FolderPlus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import type { MediaType } from "../../core/media";
import { AddToCollectionModal } from "./AddToCollectionModal";

export function AddToCollectionButton({
	mediaId,
	type,
}: {
	mediaId: number;
	type: MediaType;
}) {
	const { t } = useTranslation();
	const [opened, setOpened] = useState(false);
	return (
		<>
			<Button
				variant="light"
				leftSection={<FolderPlus size={16} />}
				onClick={() => setOpened(true)}
			>
				{t("collections.addButton")}
			</Button>
			<AddToCollectionModal
				opened={opened}
				mediaId={mediaId}
				type={type}
				onClose={() => setOpened(false)}
			/>
		</>
	);
}

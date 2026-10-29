import { Button, Group, Modal, Stack, Text, TextInput } from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCreateCollection } from "../../api/collections";
import type { MediaType } from "../../core/media";

export function CreateCollectionModal({
	opened,
	type,
	onClose,
}: {
	opened: boolean;
	type: MediaType;
	onClose: () => void;
}) {
	const { t } = useTranslation();
	const [name, setName] = useState("");
	const create = useCreateCollection();

	const close = () => {
		setName("");
		onClose();
	};

	const submit = () => {
		const trimmed = name.trim();
		if (trimmed === "") {
			return;
		}
		create.mutate(
			{ name: trimmed, type },
			{
				onSuccess: () => {
					close();
				},
			},
		);
	};

	return (
		<Modal
			opened={opened}
			onClose={close}
			title={t("collections.createTitle")}
			centered
		>
			<Stack gap="md">
				<TextInput
					label={t("collections.name")}
					value={name}
					data-autofocus
					onChange={(event) => setName(event.currentTarget.value)}
					onKeyDown={(event) => {
						if (event.key === "Enter") {
							submit();
						}
					}}
				/>
				<Group justify="flex-end">
					<Button variant="default" onClick={close}>
						{t("collections.cancel")}
					</Button>
					<Button
						onClick={submit}
						loading={create.isPending}
						disabled={name.trim() === ""}
					>
						{t("collections.create")}
					</Button>
				</Group>
				{create.isError && (
					<Text c="red" size="sm">
						{t("collections.createError")}
					</Text>
				)}
			</Stack>
		</Modal>
	);
}

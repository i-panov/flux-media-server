import { Group, Modal, Stack, Text, TextInput } from "@mantine/core";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { z } from "zod";
import { useCreateCollection } from "../../api/collections";
import type { MediaType } from "../../core/media";
import { TVButton, TVModalAutoFocus } from "../tv/tvFocus";

export function CreateCollectionModal({
	opened,
	type,
	onClose,
	onCreated,
}: {
	opened: boolean;
	type: MediaType;
	onClose: () => void;
	onCreated?: (id: number) => void;
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
				onSuccess: (body) => {
					// Сразу выбираем созданную (нужно экрану загрузки):
					// остальные вызовы onCreated не передают.
					const id = z.object({ id: z.number() }).safeParse(body);
					if (id.success) {
						onCreated?.(id.data.id);
					}
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
			<TVModalAutoFocus focusKey="create-collection-cancel" />
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
					<TVButton
						focusKey="create-collection-cancel"
						variant="default"
						onClick={close}
					>
						{t("collections.cancel")}
					</TVButton>
					<TVButton
						focusKey="create-collection-create"
						onClick={submit}
						loading={create.isPending}
						disabled={name.trim() === ""}
					>
						{t("collections.create")}
					</TVButton>
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

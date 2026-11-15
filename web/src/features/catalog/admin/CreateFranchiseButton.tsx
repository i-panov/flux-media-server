import { Alert, Button, Group, Modal, Stack, TextInput } from "@mantine/core";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCreateFranchise } from "../../../api/catalog";

export function CreateFranchiseButton() {
	const { t } = useTranslation();
	const create = useCreateFranchise();
	const [open, setOpen] = useState(false);
	const [name, setName] = useState("");
	const [description, setDescription] = useState("");
	const [coverURL, setCoverURL] = useState("");
	const [error, setError] = useState<string | null>(null);

	const submit = async () => {
		setError(null);
		try {
			await create.mutateAsync({
				name: name.trim(),
				description,
				cover_url: coverURL,
			});
			setOpen(false);
			setName("");
			setDescription("");
			setCoverURL("");
		} catch (err) {
			setError(err instanceof Error ? err.message : t("catalog.admin.error"));
		}
	};

	return (
		<>
			<Button leftSection={<Plus size={16} />} onClick={() => setOpen(true)}>
				{t("catalog.admin.add")}
			</Button>
			<Modal
				opened={open}
				onClose={() => setOpen(false)}
				title={t("catalog.admin.newFranchise")}
			>
				<Stack>
					<TextInput
						label={t("catalog.admin.title")}
						value={name}
						onChange={(event) => setName(event.currentTarget.value)}
					/>
					{error && <Alert color="red">{error}</Alert>}
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setOpen(false)}>
							{t("catalog.admin.cancel")}
						</Button>
						<Button
							loading={create.isPending}
							disabled={name.trim() === ""}
							onClick={() => void submit()}
						>
							{t("catalog.admin.create")}
						</Button>
					</Group>
				</Stack>
			</Modal>
		</>
	);
}

import {
	Alert,
	Button,
	Group,
	Modal,
	NumberInput,
	Select,
	Stack,
	TextInput,
} from "@mantine/core";
import { Plus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useCreateWork, type WorkKind } from "../../../api/catalog";

export function CreateWorkButton() {
	const { t } = useTranslation();
	const create = useCreateWork();
	const [open, setOpen] = useState(false);
	const [kind, setKind] = useState<WorkKind>("series");
	const [title, setTitle] = useState("");
	const [description, setDescription] = useState("");
	const [coverURL, setCoverURL] = useState("");
	const [year, setYear] = useState<number | string>("");
	const [error, setError] = useState<string | null>(null);

	const submit = async () => {
		setError(null);
		try {
			await create.mutateAsync({
				kind,
				title: title.trim(),
				description,
				cover_url: coverURL,
				year: typeof year === "number" ? year : undefined,
			});
			setOpen(false);
			setTitle("");
			setDescription("");
			setCoverURL("");
			setYear("");
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
				title={t("catalog.admin.newWork")}
			>
				<Stack>
					<Select
						label={t("catalog.admin.type")}
						data={[
							{ value: "series", label: t("catalog.admin.series") },
							{ value: "film_series", label: t("catalog.admin.filmSeries") },
						]}
						value={kind}
						onChange={(value) =>
							setKind(value === "film_series" ? "film_series" : "series")
						}
					/>
					<TextInput
						label={t("catalog.admin.title")}
						value={title}
						onChange={(event) => setTitle(event.currentTarget.value)}
					/>
					<TextInput
						label={t("catalog.admin.description")}
						value={description}
						onChange={(event) => setDescription(event.currentTarget.value)}
					/>
					<TextInput
						label={t("catalog.admin.coverURL")}
						value={coverURL}
						onChange={(event) => setCoverURL(event.currentTarget.value)}
					/>
					<NumberInput
						label={t("catalog.admin.year")}
						value={year}
						onChange={setYear}
						min={0}
					/>
					{error && <Alert color="red">{error}</Alert>}
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setOpen(false)}>
							{t("catalog.admin.cancel")}
						</Button>
						<Button
							loading={create.isPending}
							disabled={title.trim() === ""}
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

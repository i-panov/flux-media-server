import {
	Button,
	Card,
	Group,
	Select,
	Stack,
	Text,
	TextInput,
	Title,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { Trash2 } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
	type TagGroup,
	useCreateTag,
	useDeleteTag,
	useTags,
} from "../../api/tags";

const GROUPS: Array<{ value: TagGroup; label: string }> = [];

export function TagsAdmin() {
	const { t } = useTranslation();
	const tags = useTags();
	const create = useCreateTag();
	const remove = useDeleteTag();
	const [group, setGroup] = useState<string | null>("genre");
	const [name, setName] = useState("");
	const [slug, setSlug] = useState("");
	const groups = [
		{ value: "format", label: t("tags.format") },
		{ value: "genre", label: t("tags.genre") },
		{ value: "mood", label: t("tags.mood") },
	];

	const submit = async () => {
		if (group === null || name.trim() === "") return;
		try {
			await create.mutateAsync({
				group: group as TagGroup,
				name: name.trim(),
				slug:
					slug.trim() || name.trim().toLocaleLowerCase().replace(/\s+/g, "-"),
			});
			setName("");
			setSlug("");
		} catch {
			notifications.show({ message: t("tags.createError"), color: "red" });
		}
	};

	return (
		<Stack gap="sm">
			<Title order={2} size="h4">
				{t("tags.adminTitle")}
			</Title>
			<Card withBorder padding="md" radius="md">
				<Group align="end" wrap="wrap">
					<Select
						label={t("tags.group")}
						data={groups.length > 0 ? groups : GROUPS}
						value={group}
						onChange={setGroup}
						w={180}
					/>
					<TextInput
						label={t("tags.name")}
						value={name}
						onChange={(event) => setName(event.currentTarget.value)}
					/>
					<TextInput
						label={t("tags.slug")}
						value={slug}
						onChange={(event) => setSlug(event.currentTarget.value)}
						placeholder="film"
					/>
					<Button loading={create.isPending} onClick={() => void submit()}>
						{t("tags.create")}
					</Button>
				</Group>
			</Card>
			{tags.isPending ? (
				<Text c="dimmed">{t("common.loading")}</Text>
			) : (
				<Stack gap={4} maw={560}>
					{groups.map((g) => {
						const rows = (tags.data ?? []).filter(
							(tag) => tag.group === g.value,
						);
						if (rows.length === 0) return null;
						return (
							<Stack key={g.value} gap={4}>
								<Text fw={600} size="sm">
									{g.label}
								</Text>
								{rows.map((tag) => (
									<Group key={tag.id} justify="space-between">
										<Text size="sm">
											{tag.name}{" "}
											<Text span c="dimmed" size="xs">
												{tag.slug}
											</Text>
										</Text>
										<Button
											size="compact-xs"
											variant="subtle"
											color="red"
											aria-label={`${t("tags.delete")}: ${tag.name}`}
											onClick={() => {
												if (window.confirm(t("tags.deleteConfirm"))) {
													void remove.mutateAsync(tag.id).catch(() =>
														notifications.show({
															message: t("tags.deleteError"),
															color: "red",
														}),
													);
												}
											}}
										>
											<Trash2 size={14} />
										</Button>
									</Group>
								))}
							</Stack>
						);
					})}
				</Stack>
			)}
		</Stack>
	);
}

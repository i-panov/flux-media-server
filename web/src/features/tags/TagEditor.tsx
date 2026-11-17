import {
	Alert,
	Button,
	Group,
	Modal,
	MultiSelect,
	Select,
	Stack,
	Text,
	TextInput,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	type TagEntity,
	type TagGroup,
	useCreateTag,
	useEntityTags,
	useSetEntityTags,
	useTags,
} from "../../api/tags";

const GROUPS = ["format", "genre", "mood"] as const;

export function TagEditor({ entity, id }: { entity: TagEntity; id: number }) {
	const { t } = useTranslation();
	const tags = useTags();
	const current = useEntityTags(entity, id);
	const save = useSetEntityTags(entity, id);
	const [selected, setSelected] = useState<string[]>([]);
	const createTag = useCreateTag();
	const [createOpen, setCreateOpen] = useState(false);
	const [newGroup, setNewGroup] = useState<TagGroup>("genre");
	const [newName, setNewName] = useState("");
	const [newSlug, setNewSlug] = useState("");

	useEffect(() => {
		// eslint-disable-next-line react-hooks/set-state-in-effect -- синхронизация с загруженными тегами.
		setSelected((current.data ?? []).map((tag) => String(tag.id)));
	}, [current.data]);

	const byGroup = useMemo(() => {
		const groups: Record<string, Array<{ value: string; label: string }>> = {};
		for (const tag of tags.data ?? []) {
			groups[tag.group] ??= [];
			groups[tag.group].push({ value: String(tag.id), label: tag.name });
		}
		return groups;
	}, [tags.data]);

	const setGroup = (group: string, values: string[]) => {
		const ids = new Set(selected);
		for (const tag of tags.data ?? []) {
			if (tag.group === group) ids.delete(String(tag.id));
		}
		for (const value of values) ids.add(value);
		setSelected([...ids]);
	};

	const selectedFor = (group: string) =>
		(tags.data ?? [])
			.filter((tag) => tag.group === group && selected.includes(String(tag.id)))
			.map((tag) => String(tag.id));

	const submit = async () => {
		try {
			await save.mutateAsync(selected.map(Number));
			notifications.show({ message: t("tags.saved"), color: "green" });
		} catch {
			notifications.show({ message: t("tags.saveError"), color: "red" });
		}
	};

	return (
		<Stack gap="sm" maw={520}>
			<Text fw={600}>{t("tags.title")}</Text>
			{(current.isError || tags.isError) && (
				<Alert color="red">{t("tags.loadError")}</Alert>
			)}
			{GROUPS.map((group) => {
				const options = byGroup[group] ?? [];
				if (group === "format" && entity !== "media") return null;
				if (options.length === 0) return null;
				return group === "format" ? (
					<Select
						key={group}
						label={t("tags.format")}
						data={options}
						value={selectedFor(group)[0] ?? null}
						onChange={(value) => setGroup(group, value === null ? [] : [value])}
						clearable
					/>
				) : (
					<MultiSelect
						key={group}
						label={group === "genre" ? t("tags.genre") : t("tags.mood")}
						data={options}
						value={selectedFor(group)}
						onChange={(values) => setGroup(group, values)}
						searchable
					/>
				);
			})}
			<Group justify="space-between">
				<Button
					size="xs"
					variant="subtle"
					onClick={() => {
						setNewGroup(entity === "media" ? "genre" : "genre");
						setCreateOpen(true);
					}}
				>
					{t("tags.createInline")}
				</Button>
				<Button
					size="xs"
					loading={save.isPending}
					disabled={
						current.isPending ||
						tags.isPending ||
						current.isError ||
						tags.isError
					}
					onClick={() => void submit()}
				>
					{t("tags.save")}
				</Button>
			</Group>
			<Modal
				opened={createOpen}
				onClose={() => setCreateOpen(false)}
				title={t("tags.createInline")}
			>
				<Stack>
					<Select
						label={t("tags.group")}
						value={newGroup}
						onChange={(value) => setNewGroup((value as TagGroup) ?? "genre")}
						data={[
							{ value: "genre", label: t("tags.genre") },
							{ value: "mood", label: t("tags.mood") },
							...(entity === "media"
								? [{ value: "format", label: t("tags.format") }]
								: []),
						]}
					/>
					<TextInput
						label={t("tags.name")}
						value={newName}
						onChange={(event) => setNewName(event.currentTarget.value)}
					/>
					<TextInput
						label={t("tags.slug")}
						value={newSlug}
						onChange={(event) => setNewSlug(event.currentTarget.value)}
						placeholder="comedy"
					/>
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setCreateOpen(false)}>
							{t("common.cancel")}
						</Button>
						<Button
							loading={createTag.isPending}
							disabled={newName.trim() === ""}
							onClick={() => {
								void createTag
									.mutateAsync({
										group: newGroup,
										name: newName.trim(),
										slug:
											newSlug.trim() ||
											newName.trim().toLocaleLowerCase().replace(/\s+/g, "-"),
									})
									.then((tag) => {
										setSelected((prev) => [...prev, String(tag.id)]);
										setCreateOpen(false);
										setNewName("");
										setNewSlug("");
									})
									.catch(() =>
										notifications.show({
											message: t("tags.createError"),
											color: "red",
										}),
									);
							}}
						>
							{t("tags.create")}
						</Button>
					</Group>
				</Stack>
			</Modal>
		</Stack>
	);
}

import {
	Alert,
	Button,
	Group,
	MultiSelect,
	Select,
	Stack,
	Text,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useEffect, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	type TagEntity,
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
		<Stack gap="sm">
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
			<Group justify="flex-end">
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
		</Stack>
	);
}

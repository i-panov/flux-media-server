import { Button, Group, Select, Stack, Text } from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { CheckSquare, X } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useBulkMediaTags, useTags } from "../../api/tags";

export function BulkTagBar({
	selected,
	onClear,
	active,
	onToggleActive,
}: {
	selected: number[];
	onClear: () => void;
	active: boolean;
	onToggleActive: () => void;
}) {
	const { t } = useTranslation();
	const tags = useTags();
	const bulk = useBulkMediaTags();
	const [tagID, setTagID] = useState<string | null>(null);

	const apply = (add: boolean) => {
		if (tagID === null || selected.length === 0) return;
		bulk.mutate(
			{ mediaIDs: selected, tagID: Number(tagID), add },
			{
				onSuccess: (result) =>
					notifications.show({
						message: t("tags.bulkDone", { count: result.affected }),
						color: "green",
					}),
				onError: () =>
					notifications.show({ message: t("tags.saveError"), color: "red" }),
			},
		);
	};

	return (
		<Stack gap="xs">
			<Group gap="sm" wrap="wrap" align="end">
				<Button
					variant={active ? "filled" : "light"}
					leftSection={<CheckSquare size={16} />}
					onClick={onToggleActive}
				>
					{active ? t("tags.bulkExit") : t("tags.bulkStart")}
				</Button>
				{active && (
					<>
						<Text size="sm" c="dimmed">
							{t("tags.bulkSelected", { count: selected.length })}
						</Text>
						<Select
							placeholder={t("tags.bulkPick")}
							data={(tags.data ?? []).map((tag) => ({
								value: String(tag.id),
								label: `${tag.name} · ${tag.group}`,
							}))}
							value={tagID}
							onChange={setTagID}
							searchable
							w={{ base: "100%", sm: 260 }}
						/>
						<Button
							loading={bulk.isPending}
							disabled={tagID === null || selected.length === 0}
							onClick={() => apply(true)}
						>
							{t("tags.bulkAdd")}
						</Button>
						<Button
							variant="default"
							disabled={tagID === null || selected.length === 0}
							onClick={() => apply(false)}
						>
							{t("tags.bulkRemove")}
						</Button>
						<Button
							variant="subtle"
							leftSection={<X size={16} />}
							onClick={onClear}
						>
							{t("tags.bulkClear")}
						</Button>
					</>
				)}
			</Group>
		</Stack>
	);
}

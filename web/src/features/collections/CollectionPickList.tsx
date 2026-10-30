import { Button, Group, Loader, Stack, Text } from "@mantine/core";
import { FolderInput, FolderUp } from "lucide-react";
import { useTranslation } from "react-i18next";
import type { Collection } from "../../api/collections";
import type { MediaType } from "../../core/media";

// Общий список выбора коллекции: тот же тип, без исключённых
// (себя и потомков — иначе переезд замкнёт цикл, сервер тоже проверяет).
export function CollectionPickList({
	type,
	collections,
	excludeIds,
	allowRoot,
	pending,
	loading = false,
	onPick,
}: {
	type: MediaType;
	collections: Collection[];
	excludeIds: ReadonlySet<number>;
	allowRoot: boolean;
	pending: boolean;
	loading?: boolean;
	onPick: (id: number | null) => void;
}) {
	const { t } = useTranslation();
	if (loading) {
		return (
			<Group justify="center" py="md">
				<Loader size="sm" aria-label={t("common.loading")} />
			</Group>
		);
	}
	const matching = collections.filter(
		(collection) => collection.type === type && !excludeIds.has(collection.id),
	);
	if (!allowRoot && matching.length === 0) {
		return (
			<Text size="sm" c="dimmed">
				{t("collections.emptyForMove")}
			</Text>
		);
	}
	return (
		<Stack gap="sm">
			{allowRoot && (
				<Button
					variant="light"
					justify="flex-start"
					leftSection={<FolderUp size={16} />}
					loading={pending}
					onClick={() => onPick(null)}
				>
					{t("collections.moveToRoot")}
				</Button>
			)}
			{matching.map((collection) => (
				<Button
					key={collection.id}
					variant="light"
					justify="flex-start"
					leftSection={<FolderInput size={16} />}
					loading={pending}
					onClick={() => onPick(collection.id)}
				>
					{collection.name}
				</Button>
			))}
		</Stack>
	);
}

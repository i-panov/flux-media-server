import {
	ActionIcon,
	Button,
	Card,
	Group,
	Modal,
	Stack,
	Table,
	Text,
	Tooltip,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import type { TFunction } from "i18next";
import { Download, Trash2 } from "lucide-react";
import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import {
	downloadOriginal,
	type OriginalItem,
	useDeleteOriginal,
} from "../../api/admin";
import { ApiError } from "../../api/client";

const QUEUE_STATUSES = [
	"queued",
	"processing",
	"done",
	"error",
	"cancelled",
] as const;

const ORIGINAL_STATUSES = ["untracked", "orphaned"] as const;

function statusLabel(status: string, t: TFunction): string {
	if ((QUEUE_STATUSES as readonly string[]).includes(status)) {
		return t(`admin.queue.status.${status}`);
	}
	if ((ORIGINAL_STATUSES as readonly string[]).includes(status)) {
		return t(`admin.originals.status.${status}`);
	}
	return status;
}

function formatBytes(value: number): string {
	if (value < 1024) {
		return `${value} B`;
	}
	const units = ["KB", "MB", "GB", "TB"];
	let size = value / 1024;
	let unit = 0;
	while (size >= 1024 && unit < units.length - 1) {
		size /= 1024;
		unit += 1;
	}
	const shown = size >= 100 ? Math.round(size) : Math.round(size * 10) / 10;
	return `${shown} ${units[unit] ?? "KB"}`;
}

export function OriginalsTable({ items }: { items: OriginalItem[] }) {
	const { t } = useTranslation();
	const remove = useDeleteOriginal();
	const [pending, setPending] = useState<string | null>(null);
	const [confirm, setConfirm] = useState<string | null>(null);
	const downloadLabel = t("admin.originals.download");
	const deleteLabel = t("admin.originals.delete");

	const sorted = useMemo(
		() =>
			[...items].sort(
				(a, b) => a.views - b.views || b.size_bytes - a.size_bytes,
			),
		[items],
	);

	if (sorted.length === 0) {
		return (
			<Card withBorder padding="md" radius="md">
				<Text c="dimmed">{t("admin.originals.empty")}</Text>
			</Card>
		);
	}

	const handleDownload = (name: string) => {
		if (pending !== null) {
			return;
		}
		setPending(name);
		downloadOriginal(name)
			.then(
				(blob) => {
					const url = URL.createObjectURL(blob);
					const anchor = document.createElement("a");
					anchor.href = url;
					anchor.download = name;
					document.body.append(anchor);
					anchor.click();
					anchor.remove();
					URL.revokeObjectURL(url);
				},
				(error: unknown) => {
					notifications.show({
						color: "red",
						title: t("admin.actionError"),
						message: error instanceof ApiError ? error.message : "",
					});
				},
			)
			.finally(() => {
				setPending(null);
			});
	};

	const handleDelete = (name: string) => {
		if (remove.isPending) {
			return;
		}
		remove.mutate(name, {
			onSuccess: () => setConfirm(null),
			onError: (error: unknown) => {
				notifications.show({
					color: "red",
					title: t("admin.actionError"),
					message: error instanceof ApiError ? error.message : "",
				});
			},
		});
	};

	return (
		<>
			<Table striped highlightOnHover>
				<Table.Thead>
					<Table.Tr>
						<Table.Th>{t("admin.originals.name")}</Table.Th>
						<Table.Th>{t("admin.originals.size")}</Table.Th>
						<Table.Th>{t("admin.originals.views")}</Table.Th>
						<Table.Th>{t("admin.originals.status")}</Table.Th>
						<Table.Th>{t("admin.originals.actions")}</Table.Th>
					</Table.Tr>
				</Table.Thead>
				<Table.Tbody>
					{sorted.map((item) => (
						<Table.Tr key={item.name}>
							<Table.Td>
								<Text fw={600} truncate maw={260}>
									{item.name}
								</Text>
								<Text size="xs" c="dimmed">
									{item.modified}
								</Text>
							</Table.Td>
							<Table.Td>
								<Text size="sm">{formatBytes(item.size_bytes)}</Text>
							</Table.Td>
							<Table.Td>
								<Text size="sm">{item.views}</Text>
							</Table.Td>
							<Table.Td>
								<Text size="sm">{statusLabel(item.status, t)}</Text>
							</Table.Td>
							<Table.Td>
								<Group gap="xs">
									<Tooltip label={downloadLabel} withArrow>
										<ActionIcon
											variant="light"
											aria-label={downloadLabel}
											loading={pending === item.name}
											onClick={() => handleDownload(item.name)}
										>
											<Download size={16} />
										</ActionIcon>
									</Tooltip>
									<Tooltip label={deleteLabel} withArrow>
										<ActionIcon
											variant="light"
											color="red"
											aria-label={deleteLabel}
											onClick={() => setConfirm(item.name)}
										>
											<Trash2 size={16} />
										</ActionIcon>
									</Tooltip>
								</Group>
							</Table.Td>
						</Table.Tr>
					))}
				</Table.Tbody>
			</Table>
			<Modal
				opened={confirm !== null}
				onClose={() => setConfirm(null)}
				title={t("admin.originals.deleteTitle")}
				centered
			>
				<Stack gap="md">
					<Text size="sm">{t("admin.originals.deleteConfirm")}</Text>
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setConfirm(null)}>
							{t("collections.cancel")}
						</Button>
						<Button
							color="red"
							loading={remove.isPending}
							onClick={() => {
								if (confirm !== null) {
									handleDelete(confirm);
								}
							}}
						>
							{deleteLabel}
						</Button>
					</Group>
				</Stack>
			</Modal>
		</>
	);
}

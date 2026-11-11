import {
	ActionIcon,
	Card,
	Group,
	Progress,
	Stack,
	Table,
	Text,
	Tooltip,
} from "@mantine/core";
import type { TFunction } from "i18next";
import { RotateCcw, X } from "lucide-react";
import { useTranslation } from "react-i18next";
import type { TranscodeItem } from "../../api/transcode";

const QUEUE_STATUSES = [
	"queued",
	"processing",
	"done",
	"error",
	"cancelled",
] as const;

function formatEta(seconds: number, t: TFunction): string {
	if (seconds <= 0) {
		return t("common.emptyFallback");
	}
	const minutes = Math.floor(seconds / 60);
	const rest = Math.floor(seconds % 60);
	if (minutes <= 0) {
		return t("admin.queue.etaSeconds", { seconds: rest });
	}
	return t("admin.queue.etaMinutes", { minutes, seconds: rest });
}

function statusLabel(status: string, t: TFunction): string {
	if ((QUEUE_STATUSES as readonly string[]).includes(status)) {
		return t(`admin.queue.status.${status}`);
	}
	return status;
}

function isActive(status: string): boolean {
	return status === "queued" || status === "processing";
}

export function TranscodeQueueTable({
	items,
	retryPending,
	cancelPending,
	onRetry,
	onCancel,
}: {
	items: TranscodeItem[];
	retryPending: boolean;
	cancelPending: boolean;
	onRetry: (id: number) => void;
	onCancel: (id: number) => void;
}) {
	const { t } = useTranslation();
	if (items.length === 0) {
		return (
			<Card withBorder padding="md" radius="md">
				<Text c="dimmed">{t("admin.queue.empty")}</Text>
			</Card>
		);
	}
	return (
		<div className="admin-table-scroll">
			<Table striped highlightOnHover>
				<Table.Thead>
					<Table.Tr>
						<Table.Th>{t("admin.queue.file")}</Table.Th>
						<Table.Th>{t("admin.queue.status")}</Table.Th>
						<Table.Th>{t("admin.queue.progress")}</Table.Th>
						<Table.Th>{t("admin.queue.eta")}</Table.Th>
						<Table.Th>{t("admin.queue.error")}</Table.Th>
						<Table.Th>{t("admin.queue.actions")}</Table.Th>
					</Table.Tr>
				</Table.Thead>
				<Table.Tbody>
					{items.map((item) => (
						<Table.Tr key={item.id}>
							<Table.Td>
								<Text fw={600} truncate maw={240}>
									{item.filename}
								</Text>
							</Table.Td>
							<Table.Td>
								<Text size="sm">{statusLabel(item.status, t)}</Text>
							</Table.Td>
							<Table.Td>
								<Stack gap={4} miw={120}>
									<Progress value={item.progress} size="sm" />
									<Text size="xs" c="dimmed">
										{item.progress}%
										{item.speed > 0 ? ` · ${item.speed.toFixed(1)}x` : ""}
									</Text>
								</Stack>
							</Table.Td>
							<Table.Td>
								<Text size="sm">{formatEta(item.eta_seconds, t)}</Text>
							</Table.Td>
							<Table.Td>
								<Text
									size="sm"
									c={item.error == null ? "dimmed" : "red"}
									maw={240}
									truncate
								>
									{item.error ?? t("common.emptyFallback")}
								</Text>
							</Table.Td>
							<Table.Td>
								<Group gap="xs">
									{item.status === "error" && (
										<Tooltip label={t("admin.queue.retry")} withArrow>
											<ActionIcon
												variant="light"
												aria-label={t("admin.queue.retry")}
												loading={retryPending}
												onClick={() => onRetry(item.id)}
											>
												<RotateCcw size={16} />
											</ActionIcon>
										</Tooltip>
									)}
									{isActive(item.status) && (
										<Tooltip label={t("admin.queue.cancel")} withArrow>
											<ActionIcon
												variant="light"
												color="red"
												aria-label={t("admin.queue.cancel")}
												loading={cancelPending}
												onClick={() => onCancel(item.id)}
											>
												<X size={16} />
											</ActionIcon>
										</Tooltip>
									)}
								</Group>
							</Table.Td>
						</Table.Tr>
					))}
				</Table.Tbody>
			</Table>
		</div>
	);
}

import {
	Badge,
	Card,
	Group,
	Progress,
	Stack,
	Text,
	Title,
} from "@mantine/core";
import { useTranslation } from "react-i18next";
import type { StorageInfo } from "../../api/admin";

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

function freePercent(total: number, free: number): number {
	if (total <= 0) {
		return 0;
	}
	return Math.max(0, Math.min(100, (free / total) * 100));
}

export function StorageWidget({ data }: { data: StorageInfo }) {
	const { t } = useTranslation();
	return (
		<Stack gap="sm">
			<Group justify="space-between" align="center" wrap="wrap">
				<Title order={2} size="h4">
					{t("admin.storage.title")}
				</Title>
				<Badge
					variant="light"
					color={data.auto_cleanup ? "green" : "gray"}
					aria-label={t("admin.storage.autoCleanup")}
				>
					{t(
						data.auto_cleanup
							? "admin.storage.autoCleanupOn"
							: "admin.storage.autoCleanupOff",
					)}
				</Badge>
			</Group>
			{data.disks.map((disk) => {
				const freePct = freePercent(disk.total_bytes, disk.free_bytes);
				const low = freePct < 10;
				return (
					<Card key={disk.path} withBorder padding="md" radius="md">
						<Stack gap="xs">
							<Group justify="space-between" wrap="wrap">
								<Text fw={600} truncate>
									{disk.path}
								</Text>
								<Text size="sm" c={low ? "red" : "dimmed"}>
									{t("admin.storage.free", {
										value: formatBytes(disk.free_bytes),
										percent: Math.round(freePct),
									})}
								</Text>
							</Group>
							<Progress
								value={100 - freePct}
								color={low ? "red" : "violet"}
								aria-label={disk.path}
							/>
							<Text size="sm" c="dimmed">
								{t("admin.storage.total", {
									value: formatBytes(disk.total_bytes),
								})}
							</Text>
						</Stack>
					</Card>
				);
			})}
			<Group gap="xs" wrap="wrap">
				<Badge variant="light">
					{t("admin.storage.video", { value: formatBytes(data.video_bytes) })}
				</Badge>
				<Badge variant="light">
					{t("admin.storage.audio", { value: formatBytes(data.audio_bytes) })}
				</Badge>
				<Badge variant="light">
					{t("admin.storage.originals", {
						value: formatBytes(data.originals_bytes),
					})}
				</Badge>
				<Badge variant="light">
					{t("admin.storage.temp", { value: formatBytes(data.temp_bytes) })}
				</Badge>
			</Group>
		</Stack>
	);
}

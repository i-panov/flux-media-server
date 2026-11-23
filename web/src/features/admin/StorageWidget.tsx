import {
	Badge,
	Card,
	Group,
	Progress,
	Stack,
	Switch,
	Text,
	Title,
} from "@mantine/core";
import { notifications } from "@mantine/notifications";
import { useTranslation } from "react-i18next";
import { type StorageInfo, useSetAutoCleanup } from "../../api/admin";
import { ApiError } from "../../api/client";

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

// Несколько каталогов на одном разделе — это один диск: показываем его
// один раз, а пути перечисляем компактно.
function groupDisks(disks: StorageInfo["disks"]) {
	const groups = new Map<
		string,
		{ disk: StorageInfo["disks"][number]; usedBytes: number; paths: string[] }
	>();
	for (const disk of disks) {
		// Свободное место замеряется по каждому пути отдельно и отличается
		// на килобайты, поэтому раздел определяем по общему размеру.
		const key = String(disk.total_bytes);
		const existing = groups.get(key);
		if (existing === undefined) {
			groups.set(key, {
				disk,
				usedBytes: disk.used_bytes,
				paths: [disk.path],
			});
		} else {
			existing.usedBytes += disk.used_bytes;
			existing.paths.push(disk.path);
		}
	}
	return [...groups.values()];
}

export function StorageWidget({ data }: { data: StorageInfo }) {
	const { t } = useTranslation();
	const setAutoCleanup = useSetAutoCleanup();

	const notifyError = (error: unknown) => {
		notifications.show({
			color: "red",
			title: t("admin.actionError"),
			message: error instanceof ApiError ? error.message : "",
		});
	};

	return (
		<Stack gap="sm">
			<Group justify="space-between" align="flex-start" wrap="wrap">
				<Title order={2} size="h4">
					{t("admin.storage.title")}
				</Title>
				<Switch
					checked={data.auto_cleanup}
					disabled={setAutoCleanup.isPending}
					label={t("admin.storage.autoCleanup")}
					description={t("admin.storage.autoCleanupHint")}
					aria-label={t("admin.storage.autoCleanup")}
					onChange={(event) => {
						setAutoCleanup.mutate(event.currentTarget.checked, {
							onError: notifyError,
						});
					}}
				/>
			</Group>
			{groupDisks(data.disks).map((group) => {
				const disk = group.disk;
				const freePct = freePercent(disk.total_bytes, disk.free_bytes);
				const low = freePct < 10;
				return (
					<Card key={disk.total_bytes} withBorder padding="md" radius="md">
						<Stack gap="xs">
							<Text fw={600}>
								{t("admin.storage.diskFree", {
									free: formatBytes(disk.free_bytes),
									percent: Math.round(freePct),
								})}
							</Text>
							<Progress
								value={100 - freePct}
								color={low ? "red" : "violet"}
								aria-label={t("admin.storage.title")}
							/>
							<Group justify="space-between" gap="sm" wrap="wrap">
								<Text size="sm" c="dimmed">
									{t("admin.storage.total", {
										value: formatBytes(disk.total_bytes),
									})}
								</Text>
								<Text size="sm" c="dimmed">
									{t("admin.storage.sectionUsed", {
										value: formatBytes(group.usedBytes),
									})}
								</Text>
							</Group>
							<Stack gap={2}>
								{group.paths.map((path) => (
									<Text key={path} size="xs" c="dimmed" truncate>
										{path}
									</Text>
								))}
							</Stack>
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

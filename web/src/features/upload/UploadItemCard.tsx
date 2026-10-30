import {
	ActionIcon,
	Alert,
	Button,
	Card,
	Group,
	Loader,
	Progress,
	Stack,
	Text,
	Tooltip,
} from "@mantine/core";
import {
	CheckCircle2,
	CircleAlert,
	Copy,
	FileAudio,
	FileVideo,
	Image as ImageIcon,
	RotateCw,
	X,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import type { UploadType } from "../../api/upload";
import { formatFileSize } from "../../core/format";
import type { ItemStatus, QueueItem } from "./useUploadQueue";

function StatusIcon({ status }: { status: ItemStatus }) {
	if (status === "uploading" || status === "processing") {
		return <Loader size="sm" />;
	}
	if (status === "done") {
		return <CheckCircle2 size={20} className="text-teal-500" />;
	}
	if (status === "duplicate") {
		return <Copy size={20} className="text-orange-500" />;
	}
	if (status === "error") {
		return <CircleAlert size={20} className="text-red-500" />;
	}
	return <X size={20} className="text-[var(--mantine-color-dimmed)]" />;
}

function FileTypeIcon({ type }: { type: UploadType }) {
	const Icon =
		type === "video" ? FileVideo : type === "audio" ? FileAudio : ImageIcon;
	return <Icon size={22} className="text-[var(--mantine-color-dimmed)]" />;
}

export function UploadItemCard({
	item,
	onCancel,
	onRemove,
	onRetry,
	onForce,
}: {
	item: QueueItem;
	onCancel: () => void;
	onRemove: () => void;
	onRetry: () => void;
	onForce: () => void;
}) {
	const { t } = useTranslation();
	const active = item.status === "uploading" || item.status === "processing";
	return (
		<Card withBorder padding="sm" radius="md">
			<Group align="flex-start" wrap="nowrap" gap="sm">
				<Group gap="xs" mt={2} wrap="nowrap">
					<StatusIcon status={item.status} />
					<FileTypeIcon type={item.type} />
				</Group>
				<Stack gap={4} className="min-w-0 flex-1">
					<Text size="sm" fw={600} truncate>
						{item.file.name}
					</Text>
					<Text size="xs" c="dimmed">
						{formatFileSize(item.file.size)} ·{" "}
						{t(`upload.status.${item.status}`)}
					</Text>
					{active && (
						<Progress
							value={item.progress ?? 0}
							animated={item.progress === null}
							size="sm"
							radius="xl"
						/>
					)}
					{item.status === "duplicate" && (
						<Alert color="orange" variant="light" mt="xs">
							<Stack gap="xs">
								<Text size="sm">
									{item.duplicate === null
										? t("upload.duplicateUnknown")
										: t("upload.duplicate", {
												title: item.duplicate.title,
											})}
								</Text>
								<Button
									size="xs"
									variant="light"
									color="orange"
									onClick={onForce}
									w="fit-content"
								>
									{t("upload.force")}
								</Button>
							</Stack>
						</Alert>
					)}
					{item.status === "done" && item.collectionError !== "" && (
						<Text size="xs" c="orange">
							{t("upload.collectionError", { error: item.collectionError })}
						</Text>
					)}
					{item.status === "error" && (
						<Stack gap="xs">
							<Text size="xs" c="red">
								{item.error === "" ? t("upload.failed") : item.error}
							</Text>
							<Button
								size="xs"
								variant="light"
								leftSection={<RotateCw size={14} />}
								onClick={onRetry}
								w="fit-content"
							>
								{t("common.retry")}
							</Button>
						</Stack>
					)}
				</Stack>
				{active ? (
					<Tooltip label={t("upload.cancel")} withArrow>
						<ActionIcon
							variant="subtle"
							color="red"
							aria-label={t("upload.cancel")}
							onClick={onCancel}
						>
							<X size={18} />
						</ActionIcon>
					</Tooltip>
				) : (
					<Tooltip label={t("upload.remove")} withArrow>
						<ActionIcon
							variant="subtle"
							aria-label={t("upload.remove")}
							onClick={onRemove}
						>
							<X size={18} />
						</ActionIcon>
					</Tooltip>
				)}
			</Group>
		</Card>
	);
}

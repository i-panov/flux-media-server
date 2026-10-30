import { ActionIcon, Button, Group, Modal, Stack, Text } from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { Trash2 } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useDeleteMedia } from "../../api/media";

// Удаление медиа в корзину (только админ, вызывается из MediaAdminActions
// или строк списков): подтверждение как во Flutter, после успеха —
// назад в раздел (для строк — тот же раздел, список обновится сам),
// при ошибке модалка остаётся открытой.
export function DeleteMediaButton({
	mediaId,
	backPath,
	iconOnly,
}: {
	mediaId: number;
	backPath?: string;
	iconOnly?: boolean;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const remove = useDeleteMedia();
	const [opened, setOpened] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const deleteLabel = t("trash.deleteAction");

	const submit = () => {
		setError(null);
		remove.mutate(mediaId, {
			onSuccess: () => {
				setOpened(false);
				if (backPath !== undefined) {
					void navigate({ to: backPath });
				}
			},
			onError: (failure) => {
				setError(
					failure instanceof ApiError && failure.message !== ""
						? failure.message
						: t("trash.actionError"),
				);
			},
		});
	};

	return (
		<>
			{iconOnly === true ? (
				<ActionIcon
					variant="filled"
					color="red"
					size="lg"
					radius="xl"
					aria-label={deleteLabel}
					title={deleteLabel}
					onClick={() => setOpened(true)}
				>
					<Trash2 size={18} />
				</ActionIcon>
			) : (
				<Button
					variant="light"
					color="red"
					leftSection={<Trash2 size={16} />}
					onClick={() => setOpened(true)}
				>
					{deleteLabel}
				</Button>
			)}
			<Modal
				opened={opened}
				onClose={() => setOpened(false)}
				title={t("trash.deleteTitle")}
				centered
			>
				<Stack gap="md">
					<Text size="sm">{t("trash.deleteConfirm")}</Text>
					{error !== null && (
						<Text size="sm" c="red">
							{error}
						</Text>
					)}
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setOpened(false)}>
							{t("collections.cancel")}
						</Button>
						<Button color="red" loading={remove.isPending} onClick={submit}>
							{deleteLabel}
						</Button>
					</Group>
				</Stack>
			</Modal>
		</>
	);
}

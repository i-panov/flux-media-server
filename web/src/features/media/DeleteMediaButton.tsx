import { Button, Group, Modal, Stack, Text } from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { Trash2 } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useDeleteMedia } from "../../api/media";

// Удаление медиа в корзину (только админ, вызывается из MediaAdminActions):
// подтверждение как во Flutter, после успеха — назад в раздел,
// при ошибке модалка остаётся открытой.
export function DeleteMediaButton({
	mediaId,
	backPath,
}: {
	mediaId: number;
	backPath: string;
}) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const remove = useDeleteMedia();
	const [opened, setOpened] = useState(false);
	const [error, setError] = useState<string | null>(null);

	const submit = () => {
		setError(null);
		remove.mutate(mediaId, {
			onSuccess: () => {
				setOpened(false);
				void navigate({ to: backPath });
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
			<Button
				variant="light"
				color="red"
				leftSection={<Trash2 size={16} />}
				onClick={() => setOpened(true)}
			>
				{t("trash.deleteAction")}
			</Button>
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
							{t("trash.deleteAction")}
						</Button>
					</Group>
				</Stack>
			</Modal>
		</>
	);
}

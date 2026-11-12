import { Alert, Button, Group, Modal, Stack, Text } from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { AudioLines, Square } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useExtractAudio, useExtractedAudio } from "../../api/extract";

// Извлечение аудиодорожки из видео (только админ): подтверждение →
// джоб → опрос → ссылка на готовый трек. Уход со страницы опрос
// останавливает, задание на сервере продолжает жить.
export function ExtractAudioSection({ mediaId }: { mediaId: number }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const extracted = useExtractedAudio(mediaId);
	const flow = useExtractAudio(mediaId);
	const [confirmOpened, setConfirmOpened] = useState(false);

	const track = extracted.data ?? null;

	const confirmAndStart = () => {
		setConfirmOpened(false);
		void flow.start();
	};

	return (
		<Stack gap="xs">
			<Group gap="xs">
				{track === null ? (
					flow.isExtracting ? (
						<Button
							variant="light"
							color="red"
							leftSection={<Square size={16} />}
							onClick={() => void flow.cancel()}
						>
							{t("extract.cancel")}
						</Button>
					) : (
						<Button
							variant="light"
							leftSection={<AudioLines size={16} />}
							loading={extracted.isPending}
							onClick={() => setConfirmOpened(true)}
						>
							{t("extract.start")}
						</Button>
					)
				) : (
					<Button
						variant="light"
						leftSection={<AudioLines size={16} />}
						onClick={() => {
							void navigate({ to: "/audio" });
						}}
					>
						{t("extract.openTrack")}
					</Button>
				)}
			</Group>
			{flow.isExtracting && (
				<Text size="sm" c="dimmed">
					{t("extract.inProgress")}
				</Text>
			)}
			{extracted.isError && (
				<Button
					variant="subtle"
					size="xs"
					w="fit-content"
					onClick={() => void extracted.refetch()}
				>
					{t("common.retry")}
				</Button>
			)}
			{flow.error !== null && (
				<Alert color="red" variant="light" title={t("extract.failed")}>
					{flow.error}
				</Alert>
			)}
			<Modal
				opened={confirmOpened}
				onClose={() => setConfirmOpened(false)}
				title={t("extract.confirmTitle")}
				centered
			>
				<Stack gap="md">
					<Text size="sm">{t("extract.confirmText")}</Text>
					<Group justify="flex-end">
						<Button variant="default" onClick={() => setConfirmOpened(false)}>
							{t("collections.cancel")}
						</Button>
						<Button onClick={confirmAndStart}>{t("extract.start")}</Button>
					</Group>
				</Stack>
			</Modal>
		</Stack>
	);
}

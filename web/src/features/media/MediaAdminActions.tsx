import { Button, Group, Stack } from "@mantine/core";
import { Pencil } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useSession } from "../../api/session";
import type { Media } from "../../core/media";
import { useTVMode } from "../tv/useTVMode";
import { ExtractAudioSection } from "../video/ExtractAudioSection";
import { ChangeCoverButton } from "./ChangeCoverButton";
import { DeleteMediaButton } from "./DeleteMediaButton";
import { EditMetadataModal } from "./EditMetadataModal";

// Админские действия над медиа (как во Flutter): правка метаданных,
// замена обложки, извлечение аудио из видео. Обычным пользователям
// бэкенд всё равно ответит 403 — кнопки им не показываем.
export function MediaAdminActions({
	media,
	extractAudio,
	backPath,
}: {
	media: Media;
	extractAudio?: boolean;
	backPath: string;
}) {
	const { t } = useTranslation();
	const session = useSession();
	const { tvMode } = useTVMode();
	const [editOpened, setEditOpened] = useState(false);

	// ТВ — read-only: правка метаданных, обложка, удаление и extract
	// недоступны даже админу.
	if (tvMode || session.data?.is_admin !== true) {
		return null;
	}

	return (
		<>
			<Stack gap="xs">
				<Group gap="xs" wrap="wrap">
					<Button
						variant="light"
						leftSection={<Pencil size={16} />}
						onClick={() => setEditOpened(true)}
					>
						{t("metadata.edit")}
					</Button>
					<ChangeCoverButton mediaId={media.id} />
					<DeleteMediaButton mediaId={media.id} backPath={backPath} />
				</Group>
				{extractAudio === true && <ExtractAudioSection mediaId={media.id} />}
			</Stack>
			{/* Модалка монтируется только на время открытия: «Отмена»
			выбрасывает черновик, повторное открытие показывает данные
			медиа. При ошибке сети opened остаётся true — введённое живёт. */}
			{editOpened && (
				<EditMetadataModal
					key={media.id}
					opened
					media={media}
					onClose={() => setEditOpened(false)}
				/>
			)}
		</>
	);
}

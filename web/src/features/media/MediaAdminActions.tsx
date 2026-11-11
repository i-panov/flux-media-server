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
	const { capabilities } = useTVMode();
	const [editOpened, setEditOpened] = useState(false);

	// Read-only профиль (ТВ) скрывает write-действия даже админу;
	// возможности берём из capability-слоя, а не из одного tvMode.
	if (session.data?.is_admin !== true) {
		return null;
	}
	const canEdit = capabilities.canEditMetadata;
	const canChangeCover = capabilities.canChangeCover;
	const canDelete = capabilities.canDelete;
	if (!canEdit && !canChangeCover && !canDelete) {
		return null;
	}

	return (
		<>
			<Stack gap="xs">
				<Group gap="xs" wrap="wrap">
					{canEdit && (
						<Button
							variant="light"
							leftSection={<Pencil size={16} />}
							onClick={() => setEditOpened(true)}
						>
							{t("metadata.edit")}
						</Button>
					)}
					{canChangeCover && <ChangeCoverButton mediaId={media.id} />}
					{canDelete && (
						<DeleteMediaButton mediaId={media.id} backPath={backPath} />
					)}
				</Group>
				{extractAudio === true && canEdit && (
					<ExtractAudioSection mediaId={media.id} />
				)}
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

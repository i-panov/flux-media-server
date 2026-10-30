import { Alert, Button, FileButton, Text } from "@mantine/core";
import { ImagePlus } from "lucide-react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { useUploadCover } from "../../api/cover";

// Замена обложки (видео/аудио, только админ): JPEG/PNG/WebP до 10 МБ.
// Сервер отдаёт обложку с Cache-Control: no-cache (URL после PUT
// не меняется), поэтому превью обновляется сразу после инвалидации.
const MAX_COVER_BYTES = 10 * 1024 * 1024;

export function ChangeCoverButton({ mediaId }: { mediaId: number }) {
	const { t } = useTranslation();
	const upload = useUploadCover(mediaId);
	const [error, setError] = useState<string | null>(null);

	const pick = (file: File | null) => {
		if (file === null) {
			return;
		}
		if (file.size > MAX_COVER_BYTES) {
			setError(t("cover.tooLarge"));
			return;
		}
		setError(null);
		upload.mutate(file, {
			onError: (uploadError) => {
				setError(
					uploadError instanceof ApiError && uploadError.message !== ""
						? uploadError.message
						: t("cover.uploadError"),
				);
			},
		});
	};

	return (
		<>
			<FileButton onChange={pick} accept="image/jpeg,image/png,image/webp">
				{(props) => (
					<Button
						{...props}
						variant="light"
						leftSection={<ImagePlus size={16} />}
						loading={upload.isPending}
					>
						{t("cover.change")}
					</Button>
				)}
			</FileButton>
			{error !== null && (
				<Alert
					color="red"
					variant="light"
					mt="xs"
					onClose={() => setError(null)}
					withCloseButton
				>
					<Text size="sm">{error}</Text>
				</Alert>
			)}
		</>
	);
}

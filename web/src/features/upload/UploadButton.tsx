import { Button } from "@mantine/core";
import { useNavigate } from "@tanstack/react-router";
import { Upload } from "lucide-react";
import { useTranslation } from "react-i18next";
import { useSession } from "../../api/session";
import type { UploadType } from "../../api/upload";

// Кнопка загрузки в шапке раздела. Админ-проверка дублирует серверную:
// обычный пользователь не должен видеть недоступное действие.
export function UploadButton({ type }: { type: UploadType }) {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const session = useSession();
	if (session.data?.is_admin !== true) {
		return null;
	}
	return (
		<Button
			variant="light"
			leftSection={<Upload size={16} />}
			onClick={() => {
				void navigate({ to: "/upload", search: { type } });
			}}
		>
			{t(`upload.button.${type}`)}
		</Button>
	);
}

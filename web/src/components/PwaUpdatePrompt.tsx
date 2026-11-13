import { useRegisterSW } from "virtual:pwa-register/react";
import { Alert, Button, Group } from "@mantine/core";
import { useTranslation } from "react-i18next";

// Не активируем новый SW сами: иначе открытая вкладка запросит старый
// lazy-chunk, которого уже нет на сервере. Пользователь обновляется
// осознанно, после чего вкладка перезагружается.
export function PwaUpdatePrompt() {
	const { t } = useTranslation();
	const {
		needRefresh: [needRefresh],
		updateServiceWorker,
	} = useRegisterSW();
	if (!needRefresh) return null;
	return (
		<Alert color="blue" variant="light" title={t("pwa.updateTitle")}>
			<Group justify="space-between" gap="sm" wrap="wrap">
				{t("pwa.updateText")}
				<Button size="xs" onClick={() => void updateServiceWorker(true)}>
					{t("pwa.updateAction")}
				</Button>
			</Group>
		</Alert>
	);
}

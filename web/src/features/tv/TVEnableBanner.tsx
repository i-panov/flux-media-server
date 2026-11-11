import { Alert, Button, Group } from "@mantine/core";
import { useTranslation } from "react-i18next";
import { useTVMode } from "./useTVMode";

// Неоднозначный клиент (например, браузер с hover:none, но без ТВ-UA):
// остаёмся в обычном режиме и предлагаем включить ТВ руками. Подсказка
// запоминается в localStorage и больше не показывается.
export function TVEnableBanner() {
	const { t } = useTranslation();
	const { showTVHint, setTVMode, dismissTVHint } = useTVMode();
	if (!showTVHint) {
		return null;
	}
	return (
		<Alert
			color="violet"
			variant="light"
			title={t("tv.hint.title")}
			withCloseButton
			onClose={dismissTVHint}
			mb="md"
		>
			<Group justify="space-between" align="center" wrap="wrap" gap="sm">
				<span>{t("tv.hint.body")}</span>
				<Button
					size="xs"
					variant="light"
					onClick={() => {
						// Явное включение — это и есть ответ на подсказку: больше
						// не показываем её после будущего выключения режима.
						dismissTVHint();
						setTVMode(true);
					}}
					w="fit-content"
				>
					{t("tv.hint.enable")}
				</Button>
			</Group>
		</Alert>
	);
}

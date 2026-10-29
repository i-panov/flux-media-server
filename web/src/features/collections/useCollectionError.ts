import { notifications } from "@mantine/notifications";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";

export function useCollectionError() {
	const { t } = useTranslation();
	return (error: unknown) => {
		notifications.show({
			color: "red",
			title: t("collections.actionError"),
			message: error instanceof ApiError ? error.message : "",
		});
	};
}

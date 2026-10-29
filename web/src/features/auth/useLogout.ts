import { notifications } from "@mantine/notifications";
import { useNavigate } from "@tanstack/react-router";
import { useTranslation } from "react-i18next";
import { ApiError } from "../../api/client";
import { clearSessionData, useLogoutMutation } from "../../api/session";

// Общий выход для шапки и настроек: одна обработка 401 и одно
// уведомление об ошибке.
export function useLogout() {
	const { t } = useTranslation();
	const navigate = useNavigate();
	const mutation = useLogoutMutation();

	const logout = () => {
		mutation.mutate(undefined, {
			onSuccess: () => {
				void navigate({ to: "/login" });
			},
			onError: (error) => {
				if (error instanceof ApiError && error.status === 401) {
					// Серверная сессия уже недействительна — выходим локально.
					clearSessionData();
					void navigate({ to: "/login" });
					return;
				}
				notifications.show({
					color: "red",
					title: t("auth.logoutFailed"),
					message:
						error instanceof ApiError && error.message.length > 0
							? error.message
							: t("auth.genericError"),
				});
			},
		});
	};

	return { logout, isPending: mutation.isPending };
}

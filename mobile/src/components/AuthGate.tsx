import { Redirect, router } from "expo-router";
import type { ReactNode } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { isServerConfigured } from "../api/setup";
import { useSession } from "../auth/session";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

export function AuthGate({ children }: { children: ReactNode }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const configured = isServerConfigured();
	const session = useSession(configured);
	if (!configured) {
		return <Redirect href="/server" />;
	}
	if (session.isPending) {
		return (
			<View
				style={[
					styles.center,
					{
						backgroundColor: colors.background,
						gap: spacing.md,
					},
				]}
			>
				<ActivityIndicator color={colors.accent} />
				<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
			</View>
		);
	}
	// Сетевая/серверная ошибка при отсутствии сессии: даём «Повторить».
	// Проверяем раньше null, иначе упавший refetch с закэшированным null
	// молча уводил бы на логин.
	if (
		session.isError &&
		(session.data === undefined || session.data === null)
	) {
		// Сеть/сервер недоступны: единственный путь починить адрес — публичный
		// /server в корневом Stack. На /settings вести нельзя: он под этим же
		// AuthGate и снова покажет ошибку. Кэшированную сессию не выкидываем:
		// при isError с data ниже рендерятся табы.
		return (
			<View
				style={[
					styles.center,
					{
						backgroundColor: colors.background,
						gap: spacing.md,
					},
				]}
				testID="auth-entry"
			>
				<Text style={{ color: colors.text }}>{t("common.error")}</Text>
				<Pressable
					testID="auth-retry"
					accessibilityRole="button"
					hitSlop={8}
					style={styles.linkButton}
					onPress={() => void session.refetch()}
				>
					<Text style={[styles.link, { color: colors.accent }]}>
						{t("common.retry")}
					</Text>
				</Pressable>
				<Pressable
					testID="auth-open-server"
					accessibilityRole="button"
					hitSlop={8}
					style={styles.linkButton}
					onPress={() => router.push("/server")}
				>
					<Text style={[styles.link, { color: colors.accent }]}>
						{t("server.open")}
					</Text>
				</Pressable>
				<Pressable
					testID="auth-open-downloads"
					accessibilityRole="button"
					hitSlop={8}
					style={styles.linkButton}
					onPress={() => router.push("/downloads")}
				>
					<Text style={[styles.link, { color: colors.accent }]}>
						{t("downloads.title")}
					</Text>
				</Pressable>
				<Pressable
					testID="auth-go-login"
					accessibilityRole="button"
					hitSlop={8}
					style={styles.linkButton}
					onPress={() => router.replace("/login")}
				>
					<Text style={[styles.link, { color: colors.accent }]}>
						{t("login.title")}
					</Text>
				</Pressable>
			</View>
		);
	}
	// data === null — сессия мертва/сброшена (auth failure): штатный вход.
	if (!session.data) {
		return <Redirect href="/login" />;
	}
	return <>{children}</>;
}

const styles = StyleSheet.create({
	center: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
	},
	linkButton: {
		minHeight: 44,
		paddingHorizontal: 12,
		justifyContent: "center",
	},
	link: { fontWeight: "600" },
});

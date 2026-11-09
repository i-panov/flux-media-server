import { Redirect, router } from "expo-router";
import type { ReactNode } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useSession } from "../auth/session";
import { t, useLanguage } from "../i18n";

export function AuthGate({ children }: { children: ReactNode }) {
	useLanguage();
	const session = useSession();
	if (session.isPending) {
		return (
			<View style={styles.center}>
				<ActivityIndicator />
				<Text>{t("common.loading")}</Text>
			</View>
		);
	}
	if (session.isError && !session.data) {
		// Сеть/сервер недоступны: единственный путь починить адрес — публичный
		// /server в корневом Stack. На /settings вести нельзя: он под этим же
		// AuthGate и снова покажет ошибку. Кэшированную сессию не выкидываем:
		// при isError с data ниже рендерятся табы.
		return (
			<View style={styles.center} testID="auth-entry">
				<Text>{t("common.error")}</Text>
				<Pressable
					testID="auth-retry"
					accessibilityRole="button"
					onPress={() => void session.refetch()}
				>
					<Text style={styles.link}>{t("common.retry")}</Text>
				</Pressable>
				<Pressable
					testID="auth-open-server"
					accessibilityRole="button"
					onPress={() => router.push("/server")}
				>
					<Text style={styles.link}>{t("server.open")}</Text>
				</Pressable>
				<Pressable
					testID="auth-go-login"
					accessibilityRole="button"
					onPress={() => router.replace("/login")}
				>
					<Text style={styles.link}>{t("login.title")}</Text>
				</Pressable>
			</View>
		);
	}
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
		gap: 12,
	},
	link: { color: "#7048e8", fontWeight: "600" },
});

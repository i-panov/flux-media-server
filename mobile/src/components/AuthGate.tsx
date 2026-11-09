import { Redirect, router } from "expo-router";
import type { ReactNode } from "react";
import { ActivityIndicator, Pressable, Text, View } from "react-native";
import { useSession } from "../auth/session";
import { t, useLanguage } from "../i18n";

export function AuthGate({ children }: { children: ReactNode }) {
	useLanguage();
	const session = useSession();
	if (session.isPending) {
		return (
			<View style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
				<ActivityIndicator />
				<Text>{t("common.loading")}</Text>
			</View>
		);
	}
	if (session.isError) {
		return (
			<View
				style={{
					flex: 1,
					alignItems: "center",
					justifyContent: "center",
					gap: 12,
				}}
			>
				<Text>{t("common.error")}</Text>
				<Pressable onPress={() => void session.refetch()}>
					<Text>{t("common.retry")}</Text>
				</Pressable>
				<Pressable onPress={() => router.push("/settings")}>
					<Text>{t("home.settings")}</Text>
				</Pressable>
			</View>
		);
	}
	if (!session.data) {
		return <Redirect href="/login" />;
	}
	return <>{children}</>;
}

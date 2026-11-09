import { getApiConfig, useHealthQuery } from "@flux/shared";
import { useQueryClient } from "@tanstack/react-query";
import { Link, router } from "expo-router";
import {
	Button,
	Pressable,
	ScrollView,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { version as appVersion } from "../../package.json";
import { signOutLocal } from "../../src/auth/logout";
import { useSession } from "../../src/auth/session";
import { setLanguage, t, useLanguage } from "../../src/i18n";

export default function SettingsScreen() {
	const health = useHealthQuery();
	const session = useSession();
	const language = useLanguage();
	const queryClient = useQueryClient();

	let backendStatus: string;
	if (health.isPending) {
		backendStatus = t("common.loading");
	} else if (health.isError) {
		backendStatus = t("home.offline");
	} else {
		backendStatus = `${health.data.status} · ${health.data.version}`;
	}

	const signOut = async () => {
		await signOutLocal(queryClient);
		router.replace("/login");
	};

	return (
		<SafeAreaView
			style={styles.screen}
			edges={["top"]}
			testID="settings-screen"
		>
			<ScrollView contentContainerStyle={styles.content}>
				<Text style={styles.title}>{t("settings.title")}</Text>
				{session.data?.email !== undefined && (
					<Text style={styles.muted}>{session.data.email}</Text>
				)}

				<View style={styles.card}>
					<Text style={styles.cardTitle}>{t("home.server")}</Text>
					<Text style={styles.muted}>{backendStatus}</Text>
					<Text style={styles.muted} numberOfLines={1}>
						{getApiConfig().baseUrl}
					</Text>
					<Link href="/server" asChild>
						<Pressable testID="settings-open-server" accessibilityRole="button">
							<Text style={styles.link}>{t("server.open")}</Text>
						</Pressable>
					</Link>
				</View>

				<View style={styles.card}>
					<Text style={styles.cardTitle}>{t("settings.version")}</Text>
					<Text style={styles.muted}>{appVersion}</Text>
				</View>

				<View style={styles.card}>
					<Text style={styles.cardTitle}>{t("settings.language")}</Text>
					<View style={styles.languageRow}>
						<Button
							title="Русский"
							onPress={() => setLanguage("ru")}
							disabled={language === "ru"}
						/>
						<Button
							title="English"
							onPress={() => setLanguage("en")}
							disabled={language === "en"}
						/>
					</View>
				</View>

				{(session.data || session.isError) && (
					<Button title={t("home.logout")} onPress={() => void signOut()} />
				)}
			</ScrollView>
		</SafeAreaView>
	);
}

const styles = StyleSheet.create({
	screen: { flex: 1 },
	content: { padding: 16, gap: 12 },
	title: { fontSize: 24, fontWeight: "700" },
	card: {
		borderWidth: 1,
		borderColor: "#8884",
		borderRadius: 10,
		padding: 14,
		gap: 6,
	},
	cardTitle: { fontSize: 15, fontWeight: "600" },
	muted: { fontSize: 13, opacity: 0.6 },
	link: { color: "#7048e8", fontWeight: "600" },
	languageRow: { flexDirection: "row", gap: 12 },
});

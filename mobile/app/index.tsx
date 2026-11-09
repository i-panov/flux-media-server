import { useHealthQuery } from "@flux/shared";
import { useQueryClient } from "@tanstack/react-query";
import { Link, router } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { signOutLocal } from "../src/auth/logout";
import { useSession } from "../src/auth/session";
import { AuthGate } from "../src/components/AuthGate";
import { t, useLanguage } from "../src/i18n";

function HomeContent() {
	useLanguage();
	const session = useSession();
	const health = useHealthQuery();
	const queryClient = useQueryClient();

	const signOut = async () => {
		await signOutLocal(queryClient);
		router.replace("/login");
	};

	return (
		<SafeAreaView style={styles.screen} edges={["top", "bottom"]}>
			<View style={styles.header}>
				<View>
					<Text style={styles.title}>{t("home.title")}</Text>
					<Text style={styles.muted}>{session.data?.email}</Text>
				</View>
				<Pressable onPress={() => void signOut()}>
					<Text style={styles.link}>{t("home.logout")}</Text>
				</Pressable>
			</View>

			<View style={styles.card}>
				<Text style={styles.cardTitle}>{t("home.server")}</Text>
				<Text style={styles.muted}>
					{health.isPending
						? t("common.loading")
						: health.isError
							? t("home.offline")
							: `${health.data.status} · ${health.data.version} · ${t("home.online")}`}
				</Text>
			</View>

			<View style={styles.menu}>
				<Link href="/video" asChild>
					<Pressable style={styles.menuItem}>
						<Text style={styles.menuText}>{t("home.video")}</Text>
					</Pressable>
				</Link>
				<Link href="/audio" asChild>
					<Pressable style={styles.menuItem}>
						<Text style={styles.menuText}>{t("home.audio")}</Text>
					</Pressable>
				</Link>
				<Link href="/settings" asChild>
					<Pressable style={styles.menuItem}>
						<Text style={styles.menuText}>{t("home.settings")}</Text>
					</Pressable>
				</Link>
			</View>
		</SafeAreaView>
	);
}

export default function HomeScreen() {
	return (
		<AuthGate>
			<HomeContent />
		</AuthGate>
	);
}

const styles = StyleSheet.create({
	screen: { flex: 1, padding: 20, gap: 16 },
	header: {
		flexDirection: "row",
		justifyContent: "space-between",
		alignItems: "center",
	},
	title: { fontSize: 30, fontWeight: "700" },
	muted: { fontSize: 13, opacity: 0.6 },
	card: {
		borderWidth: 1,
		borderColor: "#8884",
		borderRadius: 10,
		padding: 14,
		gap: 4,
	},
	cardTitle: { fontSize: 15, fontWeight: "600" },
	menu: { gap: 10 },
	menuItem: { backgroundColor: "#7048e8", borderRadius: 10, padding: 16 },
	menuText: { color: "#fff", fontSize: 17, fontWeight: "600" },
	link: { color: "#7048e8", fontWeight: "600" },
});

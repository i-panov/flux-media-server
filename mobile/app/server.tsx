import {
	ACCESS_TOKEN_KEY,
	configureApi,
	getApiConfig,
	REFRESH_TOKEN_KEY,
	useHealthQuery,
} from "@flux/shared";
import { useQueryClient } from "@tanstack/react-query";
import { Link, router } from "expo-router";
import { useState } from "react";
import {
	Button,
	Pressable,
	ScrollView,
	StyleSheet,
	Text,
	TextInput,
	View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { normalizeServerUrl, SERVER_URL_KEY } from "../src/api/setup";
import { sessionQueryKey } from "../src/auth/session";
import { t, useLanguage } from "../src/i18n";
import { secureStore } from "../src/storage/secureStore";

// Публичный экран: адрес сервера задаётся до входа, поэтому AuthGate здесь
// намеренно не используется.
export default function ServerScreen() {
	useLanguage();
	const health = useHealthQuery();
	const queryClient = useQueryClient();
	const [draft, setDraft] = useState(() => getApiConfig().baseUrl);
	const [appliedUrl, setAppliedUrl] = useState(() => getApiConfig().baseUrl);
	const [error, setError] = useState<string | null>(null);
	const [saved, setSaved] = useState(false);
	const [saving, setSaving] = useState(false);

	let backendStatus: string;
	if (health.isPending) {
		backendStatus = t("common.loading");
	} else if (health.isError) {
		backendStatus = t("home.offline");
	} else {
		backendStatus = `${health.data.status} · ${health.data.version}`;
	}

	const goBack = () => {
		if (router.canGoBack()) {
			router.back();
		} else {
			router.replace("/login");
		}
	};

	const save = async (): Promise<void> => {
		const normalized = normalizeServerUrl(draft);
		if (normalized === null) {
			setError(t("settings.invalidUrl"));
			setSaved(false);
			return;
		}
		setSaving(true);
		let tokensDeleted = false;
		try {
			const changed = normalized !== appliedUrl;
			if (changed) {
				// Гасим запросы/refresh старого origin до удаления токенов:
				// иначе refresh может записать новую пару уже после del().
				await queryClient.cancelQueries();
				queryClient.removeQueries();
				await secureStore.del(ACCESS_TOKEN_KEY);
				await secureStore.del(REFRESH_TOKEN_KEY);
				tokensDeleted = true;
			}
			await secureStore.set(SERVER_URL_KEY, normalized);
			configureApi({ baseUrl: normalized });
			setAppliedUrl(normalized);
			setDraft(normalized);
			setError(null);
			setSaved(true);
			if (changed) {
				// Кэш принадлежит прежнему серверу: на новый origin его тащить
				// нельзя. removeQueries также отменяет висящий /auth/me.
				queryClient.removeQueries();
				queryClient.setQueryData(sessionQueryKey, null);
				// replace не схлопывает стек: без dismissAll после входа
				// остался бы дублирующий login/server в истории.
				if (router.canDismiss()) {
					router.dismissAll();
				}
				router.replace("/login");
				return;
			}
			await queryClient.invalidateQueries();
			if (router.canGoBack()) {
				router.back();
			} else {
				router.replace("/login");
			}
		} catch {
			setError(t("settings.saveError"));
			setSaved(false);
			if (tokensDeleted) {
				// URL не сохранился, но токенов уже нет: кэшированную сессию
				// оставлять нельзя, иначе UI покажет вход без токенов.
				queryClient.removeQueries();
				queryClient.setQueryData(sessionQueryKey, null);
				if (router.canDismiss()) {
					router.dismissAll();
				}
				router.replace("/login");
			}
		} finally {
			setSaving(false);
		}
	};

	return (
		<SafeAreaView
			style={styles.screen}
			edges={["top", "bottom"]}
			testID="server-screen"
		>
			<ScrollView contentContainerStyle={styles.content}>
				<View style={styles.header}>
					<Pressable
						onPress={goBack}
						accessibilityRole="button"
						accessibilityLabel={t("common.back")}
					>
						<Text style={styles.back}>‹</Text>
					</Pressable>
					<Text style={styles.title}>{t("server.title")}</Text>
				</View>

				<Text style={styles.hint}>{t("server.hint")}</Text>

				<View style={styles.card}>
					<Text style={styles.cardTitle}>{t("home.server")}</Text>
					<Text style={styles.muted}>{backendStatus}</Text>
					<Text style={styles.muted} numberOfLines={1}>
						{appliedUrl}
					</Text>
				</View>

				<Text style={styles.label}>{t("settings.server")}</Text>
				<TextInput
					testID="server-url"
					style={styles.input}
					value={draft}
					onChangeText={(value) => {
						setDraft(value);
						setSaved(false);
					}}
					autoCapitalize="none"
					autoCorrect={false}
					keyboardType="url"
				/>
				{error !== null && <Text style={styles.error}>{error}</Text>}
				{saved && error === null && <Text>{t("settings.saved")}</Text>}
				<Button
					testID="server-save"
					title={saving ? t("settings.saving") : t("settings.save")}
					onPress={() => void save()}
					disabled={saving}
				/>

				{!saving && (
					<Link href="/login" asChild>
						<Pressable
							testID="server-go-login"
							accessibilityRole="button"
							style={styles.loginLink}
						>
							<Text style={styles.link}>{t("login.title")}</Text>
						</Pressable>
					</Link>
				)}
			</ScrollView>
		</SafeAreaView>
	);
}

const styles = StyleSheet.create({
	screen: { flex: 1 },
	content: { padding: 16, gap: 12 },
	header: { flexDirection: "row", alignItems: "center", gap: 12 },
	title: { fontSize: 24, fontWeight: "700" },
	back: { fontSize: 30, lineHeight: 32 },
	hint: { fontSize: 14, opacity: 0.6 },
	card: {
		borderWidth: 1,
		borderColor: "#8884",
		borderRadius: 10,
		padding: 14,
		gap: 4,
	},
	cardTitle: { fontSize: 15, fontWeight: "600" },
	muted: { fontSize: 13, opacity: 0.6 },
	label: { fontSize: 13, opacity: 0.6 },
	input: {
		borderWidth: 1,
		borderColor: "#8884",
		borderRadius: 8,
		padding: 12,
		fontSize: 16,
	},
	error: { color: "#e03131" },
	loginLink: { marginTop: 8, alignSelf: "center" },
	link: { color: "#7048e8", fontWeight: "600" },
});

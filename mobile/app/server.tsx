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
import { Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import { normalizeServerUrl, SERVER_URL_KEY } from "../src/api/setup";
import { sessionQueryKey } from "../src/auth/session";
import { Screen } from "../src/components/Screen";
import { useDownloadActions } from "../src/downloads/DownloadProvider";
import { t, useLanguage } from "../src/i18n";
import { secureStore } from "../src/storage/secureStore";
import { useTheme } from "../src/theme/ThemeProvider";

// Публичный экран: адрес сервера задаётся до входа, поэтому AuthGate здесь
// намеренно не используется.
export default function ServerScreen() {
	useLanguage();
	const { colors } = useTheme();
	const health = useHealthQuery();
	const queryClient = useQueryClient();
	const { clearAll: clearDownloads } = useDownloadActions();
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
			if (changed) {
				// Файлы принадлежат прежнему origin: индекс и кеш не переносим.
				clearDownloads();
			}
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
		<Screen scroll edges={["top", "bottom"]} testID="server-screen">
			<View style={styles.header}>
				<Pressable
					onPress={goBack}
					accessibilityRole="button"
					accessibilityLabel={t("common.back")}
					hitSlop={8}
					style={styles.backButton}
				>
					<Text style={[styles.back, { color: colors.text }]}>‹</Text>
				</Pressable>
				<Text style={[styles.title, { color: colors.text }]}>
					{t("server.title")}
				</Text>
			</View>

			<Text style={[styles.hint, { color: colors.textMuted }]}>
				{t("server.hint")}
			</Text>

			<View
				style={[
					styles.card,
					{
						borderColor: colors.borderStrong,
						backgroundColor: colors.surface,
					},
				]}
			>
				<Text style={[styles.cardTitle, { color: colors.text }]}>
					{t("home.server")}
				</Text>
				<Text style={[styles.muted, { color: colors.textMuted }]}>
					{backendStatus}
				</Text>
				<Text
					style={[styles.muted, { color: colors.textMuted }]}
					numberOfLines={1}
				>
					{appliedUrl}
				</Text>
			</View>

			<Text style={[styles.label, { color: colors.textMuted }]}>
				{t("settings.server")}
			</Text>
			<TextInput
				testID="server-url"
				style={[
					styles.input,
					{
						borderColor: colors.controlBorder,
						backgroundColor: colors.surface,
						color: colors.text,
					},
				]}
				value={draft}
				onChangeText={(value) => {
					setDraft(value);
					setSaved(false);
				}}
				autoCapitalize="none"
				autoCorrect={false}
				keyboardType="url"
				placeholderTextColor={colors.textMuted}
			/>
			{error !== null && (
				<Text style={[styles.error, { color: colors.danger }]}>{error}</Text>
			)}
			{saved && error === null && (
				<Text style={[styles.saved, { color: colors.accent }]}>
					{t("settings.saved")}
				</Text>
			)}
			<Pressable
				testID="server-save"
				accessibilityRole="button"
				accessibilityState={{ disabled: saving }}
				disabled={saving}
				onPress={() => void save()}
				style={({ pressed }) => [
					styles.saveButton,
					{
						backgroundColor: colors.accent,
						opacity: saving ? 0.5 : 1,
					},
					pressed && !saving && styles.pressed,
				]}
			>
				<Text style={[styles.saveLabel, { color: colors.onAccent }]}>
					{saving ? t("settings.saving") : t("settings.save")}
				</Text>
			</Pressable>

			{!saving && (
				<Link href="/login" asChild>
					<Pressable
						testID="server-go-login"
						accessibilityRole="button"
						style={styles.loginLink}
					>
						<Text style={[styles.link, { color: colors.accent }]}>
							{t("login.title")}
						</Text>
					</Pressable>
				</Link>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	header: { flexDirection: "row", alignItems: "center", gap: 12 },
	title: { fontSize: 24, fontWeight: "700" },
	backButton: {
		minWidth: 44,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	back: { fontSize: 30, lineHeight: 32 },
	hint: { fontSize: 14 },
	card: {
		borderWidth: 1,
		borderRadius: 10,
		padding: 14,
		gap: 4,
	},
	cardTitle: { fontSize: 15, fontWeight: "600" },
	muted: { fontSize: 13 },
	label: { fontSize: 13 },
	input: {
		borderWidth: 1,
		borderRadius: 8,
		padding: 12,
		fontSize: 16,
	},
	error: { fontSize: 13 },
	saved: { fontSize: 13, fontWeight: "600" },
	saveButton: {
		borderRadius: 8,
		paddingVertical: 14,
		minHeight: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	saveLabel: { fontSize: 16, fontWeight: "600" },
	loginLink: {
		marginTop: 8,
		minHeight: 44,
		alignSelf: "center",
		justifyContent: "center",
	},
	link: { fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

import {
	ACCESS_TOKEN_KEY,
	getApiConfig,
	REFRESH_TOKEN_KEY,
	useHealthQuery,
} from "@flux/shared";
import { useQueryClient } from "@tanstack/react-query";
import { Link, router } from "expo-router";
import { useState } from "react";
import { Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import {
	applyServerUrl,
	isServerConfigured,
	normalizeServerUrl,
	SERVER_URL_KEY,
} from "../src/api/setup";
import { emitLocalReset } from "../src/auth/reset";
import { markSessionSignedOut, sessionQueryKey } from "../src/auth/session";
import { Screen } from "../src/components/Screen";
import { t, useLanguage } from "../src/i18n";
import { secureStore } from "../src/storage/secureStore";
import { useTheme } from "../src/theme/ThemeProvider";

// Публичный экран: адрес сервера задаётся до входа, поэтому AuthGate здесь
// намеренно не используется.
// eslint-disable-next-line max-lines-per-function -- экран держит форму, health и сброс сессии.
export default function ServerScreen() {
	useLanguage();
	const { colors } = useTheme();
	const [configured, setConfigured] = useState(isServerConfigured);
	const health = useHealthQuery(configured);
	const queryClient = useQueryClient();
	const [draft, setDraft] = useState(() => getApiConfig().baseUrl);
	const [appliedUrl, setAppliedUrl] = useState(() => getApiConfig().baseUrl);
	const [error, setError] = useState<string | null>(null);
	const [saved, setSaved] = useState(false);
	const [saving, setSaving] = useState(false);
	const [inputFocused, setInputFocused] = useState(false);

	let backendStatus: string;
	if (!configured) {
		backendStatus = t("server.notConfigured");
	} else if (health.isPending) {
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
				const previousSession = queryClient.getQueryData(sessionQueryKey);
				const hadSession =
					previousSession !== null && previousSession !== undefined;
				// null виден mounted useSession до удаления остального кэша:
				// иначе observers получили бы undefined и не очистили данные.
				markSessionSignedOut(queryClient);
				// Переход user → null эмитит SessionResetProvider. Если входа
				// уже не было, перехода не случится — чистим явно.
				if (!hadSession) {
					emitLocalReset();
				}
				// Оба токена удаляем независимо: ошибка одного не должна
				// оставить второй.
				await Promise.allSettled([
					secureStore.del(ACCESS_TOKEN_KEY),
					secureStore.del(REFRESH_TOKEN_KEY),
				]);
				tokensDeleted = true;
			}
			await secureStore.set(SERVER_URL_KEY, normalized);
			applyServerUrl(normalized);
			setConfigured(true);
			setAppliedUrl(normalized);
			setDraft(normalized);
			setError(null);
			setSaved(true);
			if (changed) {
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
				markSessionSignedOut(queryClient);
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
				{configured && (
					<Pressable
						onPress={goBack}
						accessibilityRole="button"
						accessibilityLabel={t("common.back")}
						hitSlop={8}
						style={styles.backButton}
					>
						<Text style={[styles.back, { color: colors.text }]}>‹</Text>
					</Pressable>
				)}
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
						borderColor: inputFocused ? colors.accent : colors.controlBorder,
						backgroundColor: colors.surface,
						color: colors.text,
					},
				]}
				value={draft}
				onChangeText={(value) => {
					setDraft(value);
					setSaved(false);
				}}
				onFocus={() => setInputFocused(true)}
				onBlur={() => setInputFocused(false)}
				onSubmitEditing={() => void save()}
				returnKeyType="go"
				blurOnSubmit
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

import {
	ACCESS_TOKEN_KEY,
	configureApi,
	getApiConfig,
	REFRESH_TOKEN_KEY,
	useHealthQuery,
} from "@flux/shared";
import { useQueryClient } from "@tanstack/react-query";
import { router } from "expo-router";
import { useState } from "react";
import { Button, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { version as appVersion } from "../package.json";
import { normalizeServerUrl, SERVER_URL_KEY } from "../src/api/setup";
import { signOutLocal } from "../src/auth/logout";
import { sessionQueryKey, useSession } from "../src/auth/session";
import { setLanguage, t, useLanguage } from "../src/i18n";
import { secureStore } from "../src/storage/secureStore";

export default function SettingsScreen() {
	const health = useHealthQuery();
	const session = useSession();
	const language = useLanguage();
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

	const save = async (): Promise<void> => {
		const normalized = normalizeServerUrl(draft);
		if (normalized === null) {
			setError(t("settings.invalidUrl"));
			setSaved(false);
			return;
		}
		setSaving(true);
		try {
			const changed = normalized !== appliedUrl;
			await secureStore.set(SERVER_URL_KEY, normalized);
			configureApi({ baseUrl: normalized });
			setAppliedUrl(normalized);
			setDraft(normalized);
			setError(null);
			setSaved(true);
			if (changed) {
				// Токены и кэш принадлежат прежнему серверу: на новый origin
				// их отправлять нельзя, иначе утечка пары access/refresh.
				await secureStore.del(ACCESS_TOKEN_KEY);
				await secureStore.del(REFRESH_TOKEN_KEY);
				queryClient.removeQueries();
				queryClient.setQueryData(sessionQueryKey, null);
				router.replace("/login");
				return;
			}
			await queryClient.invalidateQueries();
		} catch {
			setError(t("settings.saveError"));
			setSaved(false);
		} finally {
			setSaving(false);
		}
	};

	const signOut = async () => {
		await signOutLocal(queryClient);
		router.replace("/login");
	};

	return (
		<SafeAreaView edges={["top", "bottom"]}>
			<Text>{t("settings.title")}</Text>
			<Text>{t("home.server")}</Text>
			<Text>{backendStatus}</Text>
			<Text>
				{t("settings.version")}: {appVersion}
			</Text>
			<Text>{t("settings.server")}</Text>
			<Text>{appliedUrl}</Text>
			<TextInput
				value={draft}
				onChangeText={(value) => {
					setDraft(value);
					setSaved(false);
				}}
				autoCapitalize="none"
				autoCorrect={false}
				keyboardType="url"
			/>
			{error !== null && <Text>{error}</Text>}
			{saved && error === null && <Text>{t("settings.saved")}</Text>}
			<Button
				title={saving ? t("settings.saving") : t("settings.save")}
				onPress={save}
				disabled={saving}
			/>
			<Text>{t("settings.language")}</Text>
			<View style={{ flexDirection: "row", gap: 12 }}>
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
			{(session.data || session.isError) && (
				<Button title={t("home.logout")} onPress={() => void signOut()} />
			)}
		</SafeAreaView>
	);
}

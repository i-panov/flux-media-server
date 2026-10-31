import { configureApi, getApiConfig, useHealthQuery } from "@flux/shared";
import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { Button, Text, TextInput } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { version as appVersion } from "../package.json";
import { normalizeServerUrl, SERVER_URL_KEY } from "../src/api/setup";
import { secureStore } from "../src/storage/secureStore";

export default function SettingsScreen() {
	const health = useHealthQuery();
	const queryClient = useQueryClient();
	const [draft, setDraft] = useState(() => getApiConfig().baseUrl);
	const [appliedUrl, setAppliedUrl] = useState(() => getApiConfig().baseUrl);
	const [error, setError] = useState<string | null>(null);
	const [saved, setSaved] = useState(false);
	const [saving, setSaving] = useState(false);

	let backendStatus: string;
	if (health.isPending) {
		backendStatus = "Проверка соединения…";
	} else if (health.isError) {
		backendStatus = "Сервер недоступен";
	} else {
		backendStatus = `Статус: ${health.data.status}, версия ${health.data.version}`;
	}

	const save = async (): Promise<void> => {
		const normalized = normalizeServerUrl(draft);
		if (normalized === null) {
			setError("Адрес должен начинаться с http:// или https://");
			setSaved(false);
			return;
		}
		setSaving(true);
		try {
			await secureStore.set(SERVER_URL_KEY, normalized);
			configureApi({ baseUrl: normalized });
			setAppliedUrl(normalized);
			setDraft(normalized);
			setError(null);
			setSaved(true);
			await queryClient.invalidateQueries();
		} catch {
			setError("Не удалось сохранить адрес сервера");
			setSaved(false);
		} finally {
			setSaving(false);
		}
	};

	return (
		<SafeAreaView edges={["top", "bottom"]}>
			<Text>Настройки</Text>
			<Text>Сервер</Text>
			<Text>{backendStatus}</Text>
			<Text>Версия приложения: {appVersion}</Text>
			<Text>Адрес сервера</Text>
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
			{saved && error === null && <Text>Адрес сохранён</Text>}
			<Button
				title={saving ? "Сохранение…" : "Сохранить"}
				onPress={save}
				disabled={saving}
			/>
		</SafeAreaView>
	);
}

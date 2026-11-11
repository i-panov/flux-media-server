import { createQueryClient } from "@flux/shared";
import type { QueryClient } from "@tanstack/react-query";
import { QueryClientProvider } from "@tanstack/react-query";
import { Stack } from "expo-router";
import * as SplashScreen from "expo-splash-screen";
import { useEffect, useState } from "react";
import { SafeAreaProvider } from "react-native-safe-area-context";
// Импорт ради побочного эффекта (дефолт configureApi) и initApiConfig:
// модуль должен выполниться до любых запросов.
import { initApiConfig } from "../src/api/setup";
import { SessionResetProvider } from "../src/auth/SessionResetProvider";
import { DownloadProvider } from "../src/downloads/DownloadProvider";
import { setLanguage } from "../src/i18n";
import { loadLanguage } from "../src/i18n/languageStorage";
import { AudioProvider } from "../src/player/AudioProvider";
import { ThemeProvider, useTheme } from "../src/theme/ThemeProvider";

SplashScreen.preventAutoHideAsync().catch(() => {
	// Повторный вызов при Fast Refresh — не ошибка.
});

// Дерево приложения монтируется только когда готовы и API, и тема:
// иначе первый кадр после splash мог бы уйти в system-схему, хотя
// пользователь выбрал dark. Splash скрывается на следующем кадре, когда
// ThemeProvider уже применил SystemUI и Appearance к выбранной схеме.
function AppShell({
	client,
	apiReady,
}: {
	client: QueryClient;
	apiReady: boolean;
}) {
	const { hydrated } = useTheme();
	const ready = apiReady && hydrated;

	useEffect(() => {
		if (!ready) {
			return;
		}
		// Пассивные эффекты детей выполняются раньше эффектов ThemeProvider,
		// поэтому ждём следующий кадр: к нему тема уже применена к нативным
		// контролам и фону корневой вьюхи.
		const frame = requestAnimationFrame(() => {
			SplashScreen.hideAsync().catch(() => {
				// Двойной hide — не ошибка.
			});
		});
		return () => cancelAnimationFrame(frame);
	}, [ready]);

	if (!ready) {
		return null;
	}
	return (
		<QueryClientProvider client={client}>
			<SessionResetProvider>
				<DownloadProvider>
					<AudioProvider>
						<Stack screenOptions={{ headerShown: false }}>
							<Stack.Screen name="(tabs)" />
							{/* Свайп-назад iOS не должен обходить confirm о несохранённых
							    правках в редакторе метаданных. */}
							<Stack.Screen
								name="media/[id]/edit"
								options={{ gestureEnabled: false, headerShown: false }}
							/>
							<Stack.Screen
								name="player"
								options={{ presentation: "modal", headerShown: false }}
							/>
							<Stack.Screen name="login" />
							<Stack.Screen name="server" />
							<Stack.Screen name="downloads" />
						</Stack>
					</AudioProvider>
				</DownloadProvider>
			</SessionResetProvider>
		</QueryClientProvider>
	);
}

export default function RootLayout() {
	const [client] = useState(createQueryClient);
	const [ready, setReady] = useState(false);

	useEffect(() => {
		let cancelled = false;
		// Язык читаем до первого кадра: иначе выбранный в настройках ru/en
		// на мгновение перекрывался бы системной локалью. Ошибка хранилища
		// не блокирует старт — остаётся определённый по локали язык.
		const language = loadLanguage().then((stored) => {
			if (!cancelled && stored !== null) {
				setLanguage(stored);
			}
		});
		Promise.allSettled([initApiConfig(), language]).finally(() => {
			if (!cancelled) {
				setReady(true);
			}
		});
		return () => {
			cancelled = true;
		};
	}, []);

	return (
		<SafeAreaProvider>
			<ThemeProvider>
				<AppShell client={client} apiReady={ready} />
			</ThemeProvider>
		</SafeAreaProvider>
	);
}

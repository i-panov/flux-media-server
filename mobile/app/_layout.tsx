import { createQueryClient } from "@flux/shared";
import { QueryClientProvider } from "@tanstack/react-query";
import { Stack } from "expo-router";
import * as SplashScreen from "expo-splash-screen";
import { useEffect, useState } from "react";
import { SafeAreaProvider } from "react-native-safe-area-context";
// Импорт ради побочного эффекта (дефолт configureApi) и initApiConfig:
// модуль должен выполниться до любых запросов.
import { initApiConfig } from "../src/api/setup";

SplashScreen.preventAutoHideAsync().catch(() => {
	// Повторный вызов при Fast Refresh — не ошибка.
});

export default function RootLayout() {
	const [client] = useState(createQueryClient);
	const [ready, setReady] = useState(false);

	useEffect(() => {
		let cancelled = false;
		initApiConfig().finally(() => {
			if (!cancelled) {
				setReady(true);
			}
		});
		return () => {
			cancelled = true;
		};
	}, []);

	useEffect(() => {
		if (ready) {
			SplashScreen.hideAsync().catch(() => {
				// Двойной hide — не ошибка.
			});
		}
	}, [ready]);

	if (!ready) {
		return null;
	}
	return (
		<SafeAreaProvider>
			<QueryClientProvider client={client}>
				<Stack screenOptions={{ headerShown: false }}>
					<Stack.Screen name="(tabs)" />
					<Stack.Screen name="login" />
					<Stack.Screen name="server" />
				</Stack>
			</QueryClientProvider>
		</SafeAreaProvider>
	);
}

import { useHealthQuery } from "@flux/shared";
import { Link } from "expo-router";
import { Text } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

export default function HealthScreen() {
	const health = useHealthQuery();

	if (health.isPending) {
		return (
			<SafeAreaView edges={["top", "bottom"]}>
				<Link href="/settings">
					<Text>Настройки</Text>
				</Link>
				<Text>Подключение к серверу…</Text>
			</SafeAreaView>
		);
	}

	if (health.isError) {
		return (
			<SafeAreaView edges={["top", "bottom"]}>
				<Link href="/settings">
					<Text>Настройки</Text>
				</Link>
				<Text>Сервер недоступен</Text>
			</SafeAreaView>
		);
	}

	return (
		<SafeAreaView edges={["top", "bottom"]}>
			<Link href="/settings">
				<Text>Настройки</Text>
			</Link>
			<Text>
				Сервер: {health.data.status}, версия {health.data.version},{" "}
				{health.data.latencyMs} мс
			</Text>
		</SafeAreaView>
	);
}

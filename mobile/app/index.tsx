import { useHealthQuery } from "@flux/shared";
import { Text, View } from "react-native";

export default function HealthScreen() {
	const health = useHealthQuery();

	if (health.isPending) {
		return (
			<View>
				<Text>Подключение к серверу…</Text>
			</View>
		);
	}

	if (health.isError) {
		return (
			<View>
				<Text>Сервер недоступен</Text>
			</View>
		);
	}

	return (
		<View>
			<Text>
				Сервер: {health.data.status}, версия {health.data.version},{" "}
				{health.data.latencyMs} мс
			</Text>
		</View>
	);
}

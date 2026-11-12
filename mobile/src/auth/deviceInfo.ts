import { Platform } from "react-native";
import { secureStore } from "../storage/secureStore";
import { isTV } from "../tv/profile";

const DEVICE_ID_KEY = "flux-device-id";

function randomId(): string {
	return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`;
}

// Один id на установку приложения: повторные входы не должны выглядеть
// как новые устройства в списке.
export async function getDeviceIdentity(): Promise<{
	deviceId: string;
	deviceName: string;
	platform: string;
}> {
	let deviceId = await secureStore.get(DEVICE_ID_KEY);
	if (deviceId === null || deviceId === "") {
		deviceId = randomId();
		await secureStore.set(DEVICE_ID_KEY, deviceId);
	}
	const constants = Platform.constants as {
		Model?: string;
		Brand?: string;
	} | null;
	const platform = isTV ? "androidtv" : Platform.OS;
	const model = constants?.Model ?? constants?.Brand ?? "";
	const deviceName = isTV
		? "Android TV"
		: model === ""
			? Platform.OS === "ios"
				? "iPhone / iPad"
				: "Android"
			: model;
	return { deviceId, deviceName, platform };
}

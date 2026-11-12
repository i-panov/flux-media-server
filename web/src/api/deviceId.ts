const DEVICE_ID_KEY = "flux-device-id";

// Один id на браузер/профиль: все сессии с этого устройства
// группируются в одну запись, а не плодят «Устройство» на каждый вход.
export function getWebDeviceId(): string {
	try {
		const existing = window.localStorage.getItem(DEVICE_ID_KEY);
		if (existing !== null && existing !== "") return existing;
		const created =
			typeof crypto.randomUUID === "function"
				? crypto.randomUUID()
				: `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
		window.localStorage.setItem(DEVICE_ID_KEY, created);
		return created;
	} catch {
		// Приватный режим без localStorage — id живёт только до перезагрузки.
		return `session-${Date.now().toString(36)}`;
	}
}

import type { KeyValueStore } from "@flux/shared";
import * as SecureStore from "expo-secure-store";

// Единственное место, где mobile касается нативного хранилища: остальной
// код работает через KeyValueStore из shared и тестируется без девайса.
export const secureStore: KeyValueStore = {
	get: (key: string) => SecureStore.getItemAsync(key),
	set: (key: string, value: string) => SecureStore.setItemAsync(key, value),
	del: (key: string) => SecureStore.deleteItemAsync(key),
};

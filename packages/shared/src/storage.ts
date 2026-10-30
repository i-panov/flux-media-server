// Платформенно-нейтральное key-value хранилище. Реализации:
// web — localStorage-обёртка (если понадобится), mobile — expo-secure-store.
export interface KeyValueStore {
	get(key: string): Promise<string | null>;
	set(key: string, value: string): Promise<void>;
	del(key: string): Promise<void>;
}

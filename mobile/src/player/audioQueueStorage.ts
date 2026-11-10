import AsyncStorage from "@react-native-async-storage/async-storage";
import {
	AUDIO_QUEUE_STORAGE_KEY,
	type AudioQueueSnapshot,
	parseAudioQueue,
	type RestoredAudioQueue,
	serializeAudioQueue,
} from "./queuePersistence";

// Тонкая обёртка над AsyncStorage: восстановление и сериализация — чистые
// функции в queuePersistence, здесь только нативный ключ и подавление
// ошибок хранилища (недоступный AsyncStorage не должен ломать плеер).
export async function loadAudioQueue(): Promise<RestoredAudioQueue | null> {
	try {
		return parseAudioQueue(await AsyncStorage.getItem(AUDIO_QUEUE_STORAGE_KEY));
	} catch {
		return null;
	}
}

export async function saveAudioQueue(
	snapshot: AudioQueueSnapshot,
): Promise<void> {
	try {
		await AsyncStorage.setItem(
			AUDIO_QUEUE_STORAGE_KEY,
			serializeAudioQueue(snapshot),
		);
	} catch {
		// Переполнение/недоступное хранилище: очередь просто не переживёт
		// рестарт, воспроизведение продолжается.
	}
}

export async function clearAudioQueue(): Promise<void> {
	try {
		await AsyncStorage.removeItem(AUDIO_QUEUE_STORAGE_KEY);
	} catch {
		// Нечего очищать — молча пропускаем.
	}
}

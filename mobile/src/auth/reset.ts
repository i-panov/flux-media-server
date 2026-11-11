import { useEffect } from "react";

// Единая точка сброса локальных данных при выходе/смене сервера. Провайдеры
// подписываются на событие, а SessionResetProvider эмитит его на переходе
// сессии user → null. Так очистка не зависит от того, увидел ли конкретный
// observer кэша промежуточный null.

type LocalResetListener = () => void;

const listeners = new Set<LocalResetListener>();

export function subscribeLocalReset(listener: LocalResetListener): () => void {
	listeners.add(listener);
	return () => {
		listeners.delete(listener);
	};
}

export function emitLocalReset(): void {
	// Копия: слушатель может отписаться во время обхода. Ошибка одного
	// провайдера не должна мешать остальным и самому logout.
	for (const listener of [...listeners]) {
		try {
			listener();
		} catch (error) {
			console.warn("flux-reset: не удалось очистить состояние", error);
		}
	}
}

export function useLocalReset(listener: LocalResetListener): void {
	useEffect(() => subscribeLocalReset(listener), [listener]);
}

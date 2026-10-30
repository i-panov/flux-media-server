import { useEffect } from "react";
import type { AudioQueueState, RepeatMode } from "./audioQueue";
import { savePersistedQueue, savePersistedSettings } from "./playerPersistence";

// Очередь (+история shuffle) и настройки — разными ключами и эффектами:
// слайдер громкости пишет на каждый тик, и сериализовать при этом всю
// очередь не нужно. Пустую очередь не храним: после «Закрыть плеер»
// перезагрузка не должна воскрешать трек.
export function usePlayerPersistence({
	queueState,
	played,
	volume,
	shuffle,
	repeat,
}: {
	queueState: AudioQueueState;
	played: ReadonlySet<number>;
	volume: number;
	shuffle: boolean;
	repeat: RepeatMode;
}) {
	useEffect(() => {
		if (queueState.items.length === 0) {
			return;
		}
		savePersistedQueue(queueState, played);
	}, [played, queueState]);

	useEffect(() => {
		savePersistedSettings({ volume, shuffle, repeat });
	}, [repeat, shuffle, volume]);
}

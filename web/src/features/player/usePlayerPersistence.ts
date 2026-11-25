import type { AudioQueueState, RepeatMode } from "@flux/shared";
import { useEffect, useRef } from "react";
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
		// Слайдер громкости меняет значение на каждый тик: писать
		// localStorage синхронно на каждое движение незачем.
		const timer = setTimeout(() => {
			savePersistedSettings({ volume, shuffle, repeat });
		}, 300);
		return () => clearTimeout(timer);
	}, [repeat, shuffle, volume]);
}

// Настройки сохраняются при размонтировании без ожидания debounce:
// переход между экранами не должен терять последнюю громкость/режим.
export function useFlushSettingsOnUnmount({
	volume,
	shuffle,
	repeat,
}: {
	volume: number;
	shuffle: boolean;
	repeat: RepeatMode;
}) {
	const latest = useRef({ volume, shuffle, repeat });
	useEffect(() => {
		latest.current = { volume, shuffle, repeat };
	}, [repeat, shuffle, volume]);
	useEffect(
		() => () => {
			savePersistedSettings(latest.current);
		},
		[],
	);
}

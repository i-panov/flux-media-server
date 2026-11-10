import type { AudioPlayer } from "expo-audio";
import { useCallback, useState } from "react";
import { nextPlaybackRate } from "./videoControls";

export interface AudioRateState {
	rate: number;
	cycleRate: () => void;
}

// Скорость 0.5…2× тем же циклом, что у видео. Держим локально, чтобы
// быстрые тапы не зависели от задержки status.playbackRate.
export function useAudioRate(player: AudioPlayer): AudioRateState {
	const [rate, setRate] = useState(1);
	const cycleRate = useCallback(() => {
		// next считается вне setState updater: нативный вызов не должен
		// выполняться внутри updater (StrictMode вызывает его дважды).
		const next = nextPlaybackRate(rate);
		setRate(next);
		try {
			player.setPlaybackRate(next);
		} catch {
			// Нет источника — скорость применится при следующем play.
		}
	}, [player, rate]);
	return { rate, cycleRate };
}

import type { AudioPlayer } from "expo-audio";
import { useCallback } from "react";

// Seek из полного плеера: отмечает действие пользователя (поздний resume
// не должен перетереть ручную перемотку) и синхронизирует прогресс.
export function useAudioSeek(
	player: AudioPlayer,
	handleSeek: (seconds: number) => void,
	markUserStarted: () => void,
): (seconds: number) => void {
	return useCallback(
		(seconds: number) => {
			if (!Number.isFinite(seconds)) {
				return;
			}
			const position = Math.max(0, seconds);
			markUserStarted();
			handleSeek(position);
			void player.seekTo(position).catch(() => {
				// Источник ещё не загружен: seek применится при следующем play.
			});
		},
		[handleSeek, markUserStarted, player],
	);
}

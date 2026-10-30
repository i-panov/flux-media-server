import { type RefObject, useCallback } from "react";
import { playAudio } from "./audioPlayback";
import type { RepeatMode } from "./audioQueue";

// Конец трека: при повторе одного — тот же трек сначала, иначе
// автопереход дальше по очереди. Позиция уже сохранена прогрессом выше.
export function useTrackEnded({
	repeat,
	audioRef,
	markTime,
	next,
	onProgressEnded,
	onError,
}: {
	repeat: RepeatMode;
	audioRef: RefObject<HTMLAudioElement | null>;
	markTime: (seconds: number) => void;
	next: () => void;
	onProgressEnded: () => void;
	onError: (message: string) => void;
}) {
	return useCallback(() => {
		onProgressEnded();
		if (repeat === "one") {
			const element = audioRef.current;
			if (element !== null) {
				element.currentTime = 0;
				markTime(0);
				playAudio(element, onError);
			}
			return;
		}
		next();
	}, [audioRef, markTime, next, onError, onProgressEnded, repeat]);
}

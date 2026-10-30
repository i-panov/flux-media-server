import { type RefObject, useEffect, useRef } from "react";
import type { Media } from "../../core/media";
import { playAudio } from "./audioPlayback";

export function useAudioElementSync({
	current,
	volume,
	audioRef,
	shouldPlay,
	onError,
}: {
	current: Media | null;
	volume: number;
	audioRef: RefObject<HTMLAudioElement | null>;
	shouldPlay: RefObject<boolean>;
	onError: (message: string) => void;
}) {
	// Предыдущие значения — для детекта перехода: тик громкости
	// не должен дёргать play(), только смена трека или выход из паузы.
	const prevCurrentId = useRef<number | null>(null);
	const prevShouldPlay = useRef(false);
	useEffect(() => {
		const element = audioRef.current;
		if (element === null) {
			return;
		}
		if (current === null) {
			prevCurrentId.current = null;
			prevShouldPlay.current = shouldPlay.current;
			return;
		}
		element.volume = volume;
		const currentChanged = prevCurrentId.current !== current.id;
		const becamePlaying = shouldPlay.current && !prevShouldPlay.current;
		prevCurrentId.current = current.id;
		prevShouldPlay.current = shouldPlay.current;
		if (shouldPlay.current && (currentChanged || becamePlaying)) {
			playAudio(element, onError);
		}
	}, [audioRef, current, onError, shouldPlay, volume]);
}

import { type RefObject, useEffect } from "react";
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
	useEffect(() => {
		const element = audioRef.current;
		if (element === null || current === null) {
			return;
		}
		element.volume = volume;
		if (shouldPlay.current) {
			playAudio(element, onError);
		}
	}, [audioRef, current, onError, shouldPlay, volume]);
}

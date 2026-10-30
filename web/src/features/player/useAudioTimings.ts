import { useCallback, useState } from "react";

// Позиция и длительность привязаны к id трека: после переключения
// старые значения к новому файлу не относятся, а сбрасывать их
// эффектом не нужно — сравнение с currentId даёт ноль само.
export function useAudioTimings(currentId: number) {
	const [time, setTime] = useState({ mediaId: 0, seconds: 0 });
	const [loaded, setLoaded] = useState({ mediaId: 0, seconds: 0 });

	const markLoaded = useCallback(
		(seconds: number) => {
			setLoaded({ mediaId: currentId, seconds });
		},
		[currentId],
	);
	const markTime = useCallback(
		(seconds: number) => {
			setTime({ mediaId: currentId, seconds });
		},
		[currentId],
	);

	return {
		currentTime: time.mediaId === currentId ? time.seconds : 0,
		duration: loaded.mediaId === currentId ? loaded.seconds : 0,
		markLoaded,
		markTime,
	};
}

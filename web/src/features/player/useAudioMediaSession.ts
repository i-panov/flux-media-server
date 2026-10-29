import { useEffect, useRef } from "react";
import type { Media } from "../../core/media";

// Системные кнопки (наушники, локскрин, медиа-клавиши) должны идти через
// тот же toggle/next/previous, что и интерфейс: иначе пауза из системы
// не сохраняет позицию и оставляет флаг автозапуска включённым.
export function useAudioMediaSession({
	current,
	currentTime,
	duration,
	onToggle,
	next,
	previous,
}: {
	current: Media | null;
	currentTime: number;
	duration: number;
	onToggle: () => void;
	next: () => void;
	previous: () => void;
}) {
	// Колбэки новые на каждом рендере: держим их в ref, чтобы не
	// перерегистрировать обработчики и метаданные плеера постоянно.
	const actions = useRef({ onToggle, next, previous });
	useEffect(() => {
		actions.current = { onToggle, next, previous };
	}, [onToggle, next, previous]);

	useEffect(() => {
		if (!("mediaSession" in navigator)) {
			return;
		}
		navigator.mediaSession.setActionHandler("play", () => {
			actions.current.onToggle();
		});
		navigator.mediaSession.setActionHandler("pause", () => {
			actions.current.onToggle();
		});
		navigator.mediaSession.setActionHandler("nexttrack", () => {
			actions.current.next();
		});
		navigator.mediaSession.setActionHandler("previoustrack", () => {
			actions.current.previous();
		});
		return () => {
			navigator.mediaSession.setActionHandler("play", null);
			navigator.mediaSession.setActionHandler("pause", null);
			navigator.mediaSession.setActionHandler("nexttrack", null);
			navigator.mediaSession.setActionHandler("previoustrack", null);
		};
	}, []);

	useEffect(() => {
		if (current === null || !("mediaSession" in navigator)) {
			return;
		}
		navigator.mediaSession.metadata = new MediaMetadata({
			title: current.title,
			artist: current.artists.map((artist) => artist.name).join(", "),
			album: current.album,
			artwork: current.cover_url === "" ? [] : [{ src: current.cover_url }],
		});
		return () => {
			navigator.mediaSession.metadata = null;
		};
	}, [current]);

	useEffect(() => {
		if (
			current === null ||
			duration <= 0 ||
			!("mediaSession" in navigator) ||
			typeof navigator.mediaSession.setPositionState !== "function"
		) {
			return;
		}
		try {
			navigator.mediaSession.setPositionState({
				duration,
				position: Math.min(currentTime, duration),
				playbackRate: 1,
			});
		} catch {
			// Некоторые браузеры требуют строгих границ; состояние не критично.
		}
	}, [current, currentTime, duration]);
}

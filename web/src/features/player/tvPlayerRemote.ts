import { useEffect, useRef } from "react";
import { isEditableTarget, isModalOpen } from "../tv/tvBack";
import { useTVMode } from "../tv/useTVMode";
import { useAudioPlayer } from "./AudioPlayerProvider";

export type TVRemoteAction =
	| "seek-back"
	| "seek-forward"
	| "volume-down"
	| "volume-up"
	| "toggle"
	| "next"
	| "prev";

export const TV_SEEK_STEP = 10;
export const TV_VOLUME_STEP = 0.05;

// biome-ignore lint/security/noSecrets: CSS-селектор табов, не секрет.
const TABLIST_SELECTOR = '[role="tablist"]';
// biome-ignore lint/security/noSecrets: CSS-селектор слайдера, не секрет.
const SLIDER_SELECTOR = '[role="slider"]';

const MEDIA_ACTIONS: Record<string, TVRemoteAction> = {
	MediaPlayPause: "toggle",
	MediaTrackNext: "next",
	MediaTrackPrevious: "prev",
};

// keyCode-дубли media-клавиш для старых WebKit-приставок (key там
// "Unidentified"): 179 — play/pause, 176 — next, 177 — previous.
const MEDIA_KEY_CODES: Record<number, TVRemoteAction> = {
	179: "toggle",
	176: "next",
	177: "prev",
};

// Чистое решение для хука и тестов: Enter не перехватываем никогда
// (он кликает сфокусированное через onEnterPress), Back-клавиши
// принадлежат Back-хендлеру, ввод и табы живут нативно.
export function resolveTVRemoteAction(
	event: Pick<KeyboardEvent, "key" | "keyCode" | "target">,
): TVRemoteAction | null {
	const media = MEDIA_ACTIONS[event.key] ?? MEDIA_KEY_CODES[event.keyCode];
	if (media !== undefined) {
		return media;
	}
	switch (event.key) {
		case "ArrowLeft":
		case "ArrowRight":
		case "ArrowUp":
		case "ArrowDown":
			break;
		default:
			return null;
	}
	if (isModalOpen()) {
		return null;
	}
	if (event.target instanceof HTMLElement) {
		if (isEditableTarget(event.target)) {
			return null;
		}
		// Табы переключаются стрелками нативно (scoped keydown Mantine):
		// сикать поверх переключения не нужно.
		if (event.target.closest(TABLIST_SELECTOR) !== null) {
			return null;
		}
		// Слайдер двигается стрелками сам (capture-обработчик Mantine):
		// дублировать seek/volume поверх не нужно.
		if (event.target.closest(SLIDER_SELECTOR) !== null) {
			return null;
		}
	}
	switch (event.key) {
		case "ArrowLeft":
			return "seek-back";
		case "ArrowRight":
			return "seek-forward";
		case "ArrowUp":
			return "volume-up";
		default:
			return "volume-down";
	}
}

// Пульт на экране плеера (только ТВ-режим). Висит на странице плеера,
// а не в провайдере: провайдер живёт над всеми роутами, а seek/громкость
// стрелками нужны только на /player. Back-клавиши не трогаем — они уже
// уходят в router.history.back() через useTVBackNavigation.
export function useTVPlayerRemote(): void {
	const { tvMode } = useTVMode();
	const player = useAudioPlayer();
	const live = useRef(player);
	useEffect(() => {
		live.current = player;
	});

	useEffect(() => {
		if (!tvMode) {
			return;
		}
		const onKeyDown = (event: KeyboardEvent) => {
			const action = resolveTVRemoteAction(event);
			if (action === null) {
				return;
			}
			const current = live.current;
			switch (action) {
				case "seek-back":
					current.seek(Math.max(current.currentTime - TV_SEEK_STEP, 0));
					break;
				case "seek-forward": {
					const target = current.currentTime + TV_SEEK_STEP;
					current.seek(
						current.duration > 0 ? Math.min(target, current.duration) : target,
					);
					break;
				}
				case "volume-up":
					current.setVolume(current.volume + TV_VOLUME_STEP);
					break;
				case "volume-down":
					current.setVolume(current.volume - TV_VOLUME_STEP);
					break;
				case "toggle":
					current.toggle();
					break;
				case "next":
					current.next();
					break;
				case "prev":
					current.previous();
					break;
			}
		};
		window.addEventListener("keydown", onKeyDown);
		return () => {
			window.removeEventListener("keydown", onKeyDown);
		};
	}, [tvMode]);
}

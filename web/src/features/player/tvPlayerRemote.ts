import { getCurrentFocusKey } from "@noriginmedia/norigin-spatial-navigation";
import { type RefObject, useEffect, useRef } from "react";
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

// Видео-OSD: те же шаги, что у аудиоплеера, плюс полный экран и mute.
const VIDEO_SEEK_BACK = "seek-back" as const;
const VIDEO_SEEK_FORWARD = "seek-forward" as const;
const VIDEO_VOLUME_DOWN = "volume-down" as const;
const VIDEO_VOLUME_UP = "volume-up" as const;
const VIDEO_TOGGLE = "toggle" as const;
const VIDEO_TOGGLE_MUTE = "toggle-mute" as const;
const VIDEO_FULLSCREEN = "fullscreen" as const;

export type TVVideoRemoteAction =
	| typeof VIDEO_SEEK_BACK
	| typeof VIDEO_SEEK_FORWARD
	| typeof VIDEO_VOLUME_DOWN
	| typeof VIDEO_VOLUME_UP
	| typeof VIDEO_TOGGLE
	| typeof VIDEO_TOGGLE_MUTE
	| typeof VIDEO_FULLSCREEN;

const VIDEO_MEDIA_ACTIONS: Record<string, TVVideoRemoteAction> = {
	MediaPlayPause: VIDEO_TOGGLE,
	MediaTrackNext: VIDEO_SEEK_FORWARD,
	MediaTrackPrevious: VIDEO_SEEK_BACK,
};

// keyCode-дубли media-клавиш для старых WebKit-приставок (key там
// "Unidentified"): 179 — play/pause, 176 — next, 177 — previous.
const VIDEO_MEDIA_KEY_CODES: Record<number, TVVideoRemoteAction> = {
	179: VIDEO_TOGGLE,
	176: VIDEO_SEEK_FORWARD,
	177: VIDEO_SEEK_BACK,
};

export function clampTVSeek(
	currentTime: number,
	delta: number,
	duration: number,
): number {
	const target = (Number.isFinite(currentTime) ? currentTime : 0) + delta;
	// У прямого эфира/ещё не загруженного элемента duration = Infinity/0:
	// верхнюю границу не навязываем, только не уходим в отрицательное.
	const upper =
		Number.isFinite(duration) && duration > 0
			? duration
			: Number.POSITIVE_INFINITY;
	return Math.min(Math.max(target, 0), upper);
}

export function clampTVVolume(volume: number): number {
	const value = Number.isFinite(volume) ? volume : 0;
	return Math.min(Math.max(value, 0), 1);
}

const INTERACTIVE_SELECTOR =
	"button, a, input, textarea, select, [role='button'], [role='link'], [role='slider'], [role='tab']";
// Только кнопки/ссылки, которые сами умеют стрелки: слайдер и табы
// обрабатываются отдельно, чтобы не потерять их нативное поведение.
const ARROW_INTERACTIVE_SELECTOR =
	"button, a, input, textarea, select, [role='button'], [role='link'], [role='tab'], [role='slider']";
const OSD_FOCUS_KEY_PREFIX = "video-osd-";

function isInteractiveTarget(target: EventTarget | null): boolean {
	return (
		target instanceof HTMLElement &&
		target.closest(INTERACTIVE_SELECTOR) !== null
	);
}

function currentSpatialFocusKey(): string | null {
	try {
		const key = getCurrentFocusKey();
		return typeof key === "string" && key !== "" ? key : null;
	} catch {
		// spatial ещё не инициализирован.
		return null;
	}
}

function osdFocusKey(target: EventTarget | null): string | null {
	if (!(target instanceof HTMLElement)) {
		return null;
	}
	const node = target.closest<HTMLElement>(
		`[data-tv-focus-key^="${OSD_FOCUS_KEY_PREFIX}"]`,
	);
	return node?.getAttribute("data-tv-focus-key") ?? null;
}

function resolveVideoArrowAction(
	event: Pick<KeyboardEvent, "key" | "target">,
	focusKey: string | null,
): TVVideoRemoteAction | null {
	if (focusKey !== null) {
		// На play ←/→ остаются глобальным seek (spatial их не двигает),
		// а ↑/↓ отдаются spatial-навигации к другим кнопкам/странице.
		if (
			focusKey === "video-osd-play" &&
			(event.key === "ArrowLeft" || event.key === "ArrowRight")
		) {
			return event.key === "ArrowLeft" ? VIDEO_SEEK_BACK : VIDEO_SEEK_FORWARD;
		}
		// Остальные OSD-кнопки и слайдеры ведут себя нативно: глобальный
		// seek/volume поверх spatial-навигации не нужен.
		return null;
	}
	if (
		event.target instanceof HTMLElement &&
		event.target.closest(`${TABLIST_SELECTOR}, ${SLIDER_SELECTOR}`) !== null
	) {
		return null;
	}
	// Фокус на обычной кнопке/ссылке вне OSD: стрелки — навигация,
	// а не глобальный seek. Up/Down-громкость остаётся для контейнера
	// и фона, где spatial-фокус не занимает кнопку.
	if (
		event.target instanceof HTMLElement &&
		event.target.closest(ARROW_INTERACTIVE_SELECTOR) !== null
	) {
		return null;
	}
	switch (event.key) {
		case "ArrowLeft":
			return VIDEO_SEEK_BACK;
		case "ArrowRight":
			return VIDEO_SEEK_FORWARD;
		case "ArrowUp":
			return VIDEO_VOLUME_UP;
		default:
			return VIDEO_VOLUME_DOWN;
	}
}

// Пульт на видео-OSD. Enter/Space не перехватываем на кнопках и ссылках:
// их нативно/через spatial уже активирует фокус, иначе действие
// сыграло бы дважды. Стрелки на слайдере двигает сам Slider.
export function resolveTVVideoRemoteAction(
	event: Pick<KeyboardEvent, "key" | "keyCode" | "target">,
	spatialFocusKey?: string | null,
): TVVideoRemoteAction | null {
	// Модалка/меню забирают и media-клавиши: иначе плеер под открытым
	// слоем неожиданно переключался бы с пульта.
	if (isModalOpen()) {
		return null;
	}
	const media =
		VIDEO_MEDIA_ACTIONS[event.key] ?? VIDEO_MEDIA_KEY_CODES[event.keyCode];
	if (media !== undefined) {
		return media;
	}
	if (isEditableTarget(event.target)) {
		return null;
	}
	// DOM-фокус мог потеряться (inert), но norigin помнит OSD-цель:
	// Enter/Space тогда кликает spatial, а не глобальный toggle.
	const focusKey =
		osdFocusKey(event.target) ??
		(spatialFocusKey?.startsWith(OSD_FOCUS_KEY_PREFIX)
			? spatialFocusKey
			: null);
	switch (event.key) {
		case "f":
		case "F":
			return VIDEO_FULLSCREEN;
		case "m":
		case "M":
			return VIDEO_TOGGLE_MUTE;
		case "Enter":
		case " ":
		case "Spacebar":
			// На кнопке/ссылке или OSD-цели Enter/Space уже активируют фокус.
			return focusKey !== null || isInteractiveTarget(event.target)
				? null
				: VIDEO_TOGGLE;
		case "ArrowLeft":
		case "ArrowRight":
		case "ArrowUp":
		case "ArrowDown":
			return resolveVideoArrowAction(event, focusKey);
		default:
			return null;
	}
}

export function toggleVideoPlayback(video: HTMLVideoElement): void {
	if (video.paused || video.ended) {
		void video.play().catch(() => {
			// Автоплей может быть запрещён политикой браузера: остаёмся
			// на паузе, пользователь повторит Enter.
		});
		return;
	}
	video.pause();
}

export function seekVideoBy(video: HTMLVideoElement, seconds: number): void {
	video.currentTime = clampTVSeek(video.currentTime, seconds, video.duration);
}

export function changeVideoVolume(
	video: HTMLVideoElement,
	delta: number,
): void {
	video.volume = clampTVVolume(video.volume + delta);
	if (video.volume > 0) {
		video.muted = false;
	}
}

export function toggleVideoMute(video: HTMLVideoElement): void {
	video.muted = !video.muted;
	if (!video.muted && video.volume === 0) {
		video.volume = TV_VOLUME_STEP;
	}
}

// Старый WebKit (часть ТВ-браузеров) не знает стандартных имён.
interface WebkitFullscreenElement extends HTMLElement {
	webkitRequestFullscreen?: () => void;
}

interface WebkitFullscreenDocument extends Document {
	webkitFullscreenElement?: Element | null;
	webkitExitFullscreen?: () => void;
}

export function isTVFullscreenActive(): boolean {
	const doc = document as WebkitFullscreenDocument;
	return (
		(doc.fullscreenElement ?? doc.webkitFullscreenElement ?? null) !== null
	);
}

export function canRequestTVFullscreen(target: Element | null): boolean {
	return (
		target instanceof HTMLElement &&
		(typeof target.requestFullscreen === "function" ||
			typeof (target as WebkitFullscreenElement).webkitRequestFullscreen ===
				"function")
	);
}

export async function exitTVFullscreen(): Promise<void> {
	const doc = document as WebkitFullscreenDocument;
	try {
		if (!isTVFullscreenActive()) {
			return;
		}
		if (typeof doc.exitFullscreen === "function") {
			await doc.exitFullscreen();
			return;
		}
		doc.webkitExitFullscreen?.();
	} catch {
		// Браузер мог уже выйти из fullscreen сам.
	}
}

// Fullscreen запрашиваем на контейнере плеера, а не на <video>: иначе
// OSD остался бы вне полноэкранного слоя. На старых WebKit — webkit-ветка.
export async function toggleTVFullscreen(
	target: Element | null,
): Promise<void> {
	if (isTVFullscreenActive()) {
		await exitTVFullscreen();
		return;
	}
	try {
		if (!(target instanceof HTMLElement)) {
			return;
		}
		if (typeof target.requestFullscreen === "function") {
			await target.requestFullscreen();
			return;
		}
		(target as WebkitFullscreenElement).webkitRequestFullscreen?.();
	} catch {
		// Старые ТВ-браузеры могут не разрешать fullscreen без жеста или
		// вовсе его не поддерживать — молча оставляем текущий режим.
	}
}

export interface TVVideoRemoteOptions {
	videoRef: RefObject<HTMLVideoElement | null>;
	// Любая клавиша показывает OSD и сбрасывает таймер автоскрытия.
	onActivity: () => void;
}

// Клавиатурный пульт видео-OSD. Back/Escape не трогаем: их обрабатывает
// глобальный useTVBackNavigation (router.history.back()).
export function useTVVideoRemote({
	videoRef,
	onActivity,
}: TVVideoRemoteOptions): void {
	const live = useRef({ videoRef, onActivity });
	useEffect(() => {
		live.current = { videoRef, onActivity };
	});

	useEffect(() => {
		const onKeyDown = (event: KeyboardEvent) => {
			live.current.onActivity();
			const action = resolveTVVideoRemoteAction(
				event,
				currentSpatialFocusKey(),
			);
			if (action === null) {
				return;
			}
			const video = live.current.videoRef.current;
			if (video === null) {
				return;
			}
			event.preventDefault();
			runVideoRemoteAction(action, video);
		};
		window.addEventListener("keydown", onKeyDown);
		return () => {
			window.removeEventListener("keydown", onKeyDown);
		};
	}, []);
}

function runVideoRemoteAction(
	action: TVVideoRemoteAction,
	video: HTMLVideoElement,
): void {
	switch (action) {
		case VIDEO_SEEK_BACK:
			seekVideoBy(video, -TV_SEEK_STEP);
			break;
		case VIDEO_SEEK_FORWARD:
			seekVideoBy(video, TV_SEEK_STEP);
			break;
		case VIDEO_VOLUME_UP:
			changeVideoVolume(video, TV_VOLUME_STEP);
			break;
		case VIDEO_VOLUME_DOWN:
			changeVideoVolume(video, -TV_VOLUME_STEP);
			break;
		case VIDEO_TOGGLE:
			toggleVideoPlayback(video);
			break;
		case VIDEO_TOGGLE_MUTE:
			toggleVideoMute(video);
			break;
		case VIDEO_FULLSCREEN:
			void toggleTVFullscreen(video.parentElement ?? video);
			break;
	}
}

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
			return VIDEO_SEEK_BACK;
		case "ArrowRight":
			return VIDEO_SEEK_FORWARD;
		case "ArrowUp":
			return VIDEO_VOLUME_UP;
		default:
			return VIDEO_VOLUME_DOWN;
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

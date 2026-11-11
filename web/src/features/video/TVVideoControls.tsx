import { ActionIcon, Group, Text } from "@mantine/core";
import {
	getCurrentFocusKey,
	setFocus,
} from "@noriginmedia/norigin-spatial-navigation";
import { ArrowLeft } from "lucide-react";
import {
	type RefObject,
	useCallback,
	useEffect,
	useRef,
	useState,
} from "react";
import { useTranslation } from "react-i18next";
import {
	canRequestTVFullscreen,
	exitTVFullscreen,
	isTVFullscreenActive,
	toggleTVFullscreen,
	useTVVideoRemote,
} from "../player/tvPlayerRemote";
import { isBackKey, isEditableTarget, isModalOpen } from "../tv/tvBack";
import { clickNode, useTVFocusable } from "../tv/tvFocus";
import {
	BottomControls,
	TransportControls,
	type VideoSnapshot,
} from "./TVVideoControlsParts";
import { useTVVideoOSDPointerActivity } from "./useTVVideoOSDPointerActivity";

const OSD_HIDE_DELAY_MS = 3000;
const SAFE_RESTORE_FOCUS_KEY = "video-osd-play";
const SLIDER_FOCUS_KEYS: ReadonlySet<string> = new Set([
	"video-osd-timeline",
	"video-osd-volume",
]);

const EMPTY_SNAPSHOT: VideoSnapshot = {
	playing: false,
	currentTime: 0,
	duration: 0,
	volume: 1,
	muted: false,
	fullscreen: false,
	fullscreenAvailable: false,
};

function readSnapshot(video: HTMLVideoElement): VideoSnapshot {
	return {
		playing: !video.paused && !video.ended,
		currentTime: Number.isFinite(video.currentTime) ? video.currentTime : 0,
		duration: Number.isFinite(video.duration) ? video.duration : 0,
		volume: Number.isFinite(video.volume) ? video.volume : 1,
		muted: video.muted,
		fullscreen: isTVFullscreenActive(),
		fullscreenAvailable: canRequestTVFullscreen(video.parentElement),
	};
}

// Состояние читаем из самого <video>: play/pause, seek и прогресс
// остаются за нативным элементом, OSD только отображает и командует.
// timeupdate слушаем только при видимой панели: скрытый OSD не тратит
// рендеры на каждое обновление позиции.
function useVideoSnapshot(
	videoRef: RefObject<HTMLVideoElement | null>,
	videoNonce: number,
	visibleRef: RefObject<boolean>,
): { snapshot: VideoSnapshot; refresh: () => void } {
	const [snapshot, setSnapshot] = useState(EMPTY_SNAPSHOT);
	const refresh = useCallback(() => {
		const video = videoRef.current;
		if (video !== null) {
			setSnapshot(readSnapshot(video));
		}
	}, [videoRef]);

	// biome-ignore lint/correctness/useExhaustiveDependencies: videoNonce — триггер перемонтирования <video> после ошибки потока.
	useEffect(() => {
		const video = videoRef.current;
		if (video === null) {
			return;
		}
		const sync = () => {
			setSnapshot(readSnapshot(video));
		};
		const syncIfVisible = () => {
			if (visibleRef.current) {
				sync();
			}
		};
		sync();
		const mediaEvents = [
			"play",
			"pause",
			"durationchange",
			"loadedmetadata",
			"ended",
			"volumechange",
		] as const;
		for (const event of mediaEvents) {
			video.addEventListener(event, sync);
		}
		video.addEventListener("timeupdate", syncIfVisible);
		document.addEventListener("fullscreenchange", sync);
		document.addEventListener("webkitfullscreenchange", sync);
		return () => {
			for (const event of mediaEvents) {
				video.removeEventListener(event, sync);
			}
			video.removeEventListener("timeupdate", syncIfVisible);
			document.removeEventListener("fullscreenchange", sync);
			document.removeEventListener("webkitfullscreenchange", sync);
		};
		// videoNonce — перемонтирование <video> после ошибки потока:
		// слушатели нужно повесить на новый элемент.
	}, [videoRef, videoNonce, visibleRef]);

	return { snapshot, refresh };
}

function readFocusKey(): string | null {
	try {
		const key = getCurrentFocusKey();
		return typeof key === "string" && key.startsWith("video-osd-") ? key : null;
	} catch {
		// spatial ещё не инициализирован.
		return null;
	}
}

// inert снимает фокус только с узлов внутри OSD. Если пользователь ушёл
// на страницу, возвращать ему play не нужно.
function focusWasLost(): boolean {
	const active = document.activeElement;
	if (active === null || active === document.body) {
		return true;
	}
	return (
		active instanceof HTMLElement && active.closest(".tv-video-osd") !== null
	);
}

function isOSDRevealKey(key: string): boolean {
	return (
		key === "Enter" ||
		key === " " ||
		key === "Spacebar" ||
		key.startsWith("Arrow")
	);
}

function useOSDVisibility(playing: boolean): {
	visible: boolean;
	show: () => void;
} {
	const [hidden, setHidden] = useState(false);
	const hiddenRef = useRef(false);
	const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
	const lastFocusKey = useRef(SAFE_RESTORE_FOCUS_KEY);
	const playingRef = useRef(playing);
	useEffect(() => {
		playingRef.current = playing;
	}, [playing]);

	const setHiddenState = useCallback((value: boolean) => {
		hiddenRef.current = value;
		setHidden(value);
	}, []);

	const clearHideTimer = useCallback(() => {
		if (hideTimer.current !== null) {
			clearTimeout(hideTimer.current);
			hideTimer.current = null;
		}
	}, []);

	const scheduleHide = useCallback(() => {
		clearHideTimer();
		if (!playingRef.current) {
			return;
		}
		hideTimer.current = setTimeout(() => {
			hideTimer.current = null;
			const current = readFocusKey();
			lastFocusKey.current =
				current !== null && !SLIDER_FOCUS_KEYS.has(current)
					? current
					: SAFE_RESTORE_FOCUS_KEY;
			setHiddenState(true);
		}, OSD_HIDE_DELAY_MS);
	}, [clearHideTimer, setHiddenState]);

	const show = useCallback(() => {
		const wasHidden = hiddenRef.current;
		setHiddenState(false);
		if (wasHidden && focusWasLost()) {
			// inert снимает DOM-фокус; возвращаем его на последнюю
			// безопасную OSD-цель после перерисовки. Это не зависит от
			// playing: пауза могла случиться уже после автоскрытия.
			const key = SLIDER_FOCUS_KEYS.has(lastFocusKey.current)
				? SAFE_RESTORE_FOCUS_KEY
				: lastFocusKey.current;
			setTimeout(() => {
				void setFocus(key);
			}, 0);
		}
		scheduleHide();
	}, [scheduleHide, setHiddenState]);

	useEffect(() => {
		clearHideTimer();
		if (playing) {
			scheduleHide();
			return clearHideTimer;
		}
		// На паузе OSD остаётся на экране и, если был скрыт, получает
		// фокус обратно.
		// eslint-disable-next-line react-hooks/set-state-in-effect -- show() возвращает OSD и фокус после паузы.
		show();
		return clearHideTimer;
	}, [playing, scheduleHide, clearHideTimer, show]);

	return { visible: !hidden, show };
}

export function TVVideoControls({
	videoRef,
	videoNonce,
	onBack,
}: {
	videoRef: RefObject<HTMLVideoElement | null>;
	videoNonce: number;
	onBack: () => void;
}) {
	const { t } = useTranslation();
	const visibleRef = useRef(true);
	const { snapshot, refresh } = useVideoSnapshot(
		videoRef,
		videoNonce,
		visibleRef,
	);
	const { visible, show } = useOSDVisibility(snapshot.playing);
	useEffect(() => {
		visibleRef.current = visible;
	}, [visible]);
	useTVVideoOSDPointerActivity(show, visible, videoRef);
	useTVVideoRemote({ videoRef, onActivity: show });
	const [seekPreview, setSeekPreview] = useState<number | null>(null);
	useEffect(() => {
		if (visible) {
			refresh();
		}
	}, [visible, refresh]);

	// Back в fullscreen сначала выходит из него, а не уводит со страницы.
	// Capture-фаза: глобальный useTVBackNavigation слушает window bubble.
	useEffect(() => {
		const onKeyDown = (event: KeyboardEvent) => {
			if (
				!isTVFullscreenActive() ||
				!isBackKey(event) ||
				isEditableTarget(event.target) ||
				isModalOpen()
			) {
				return;
			}
			event.preventDefault();
			event.stopPropagation();
			void exitTVFullscreen();
		};
		window.addEventListener("keydown", onKeyDown, true);
		return () => {
			window.removeEventListener("keydown", onKeyDown, true);
		};
	}, []);

	// Скрытый OSD: первый Enter/Space/стрелка только показывает панель и
	// возвращает DOM-фокус. Иначе norigin помнит focusKey на play, spatial
	// кликает кнопку, а глобальный handler дублирует toggle/mute.
	useEffect(() => {
		const onKeyDownCapture = (event: KeyboardEvent) => {
			if (
				visibleRef.current ||
				!isOSDRevealKey(event.key) ||
				isEditableTarget(event.target) ||
				isModalOpen()
			) {
				return;
			}
			event.preventDefault();
			event.stopImmediatePropagation();
			show();
		};
		window.addEventListener("keydown", onKeyDownCapture, true);
		return () => {
			window.removeEventListener("keydown", onKeyDownCapture, true);
		};
	}, [show]);

	const { targetRef: backRef } = useTVFocusable<HTMLButtonElement>(
		"video-osd-back",
		clickNode,
		undefined,
		{ secondary: true },
	);

	const run = (action: (video: HTMLVideoElement) => void) => {
		const video = videoRef.current;
		if (video !== null) {
			action(video);
		}
	};
	const duration = Math.max(snapshot.duration, 1);
	const displayTime = seekPreview ?? snapshot.currentTime;
	const onFullscreen = () => {
		const video = videoRef.current;
		void toggleTVFullscreen(video?.parentElement ?? video);
	};

	return (
		<section
			className="tv-video-osd"
			data-visible={visible ? "true" : "false"}
			data-playing={snapshot.playing ? "true" : "false"}
			data-testid="tv-video-osd"
			aria-label={t("video.osd.region")}
			aria-hidden={!visible}
			inert={!visible}
		>
			<Group justify="space-between" className="tv-video-osd__top">
				<ActionIcon
					variant="subtle"
					color="gray"
					c="white"
					size="lg"
					radius="xl"
					ref={backRef}
					aria-label={t("video.back")}
					onClick={onBack}
				>
					<ArrowLeft size={24} />
				</ActionIcon>
				<Text size="sm" className="tv-video-osd__state">
					{snapshot.playing ? t("video.osd.playing") : t("video.osd.paused")}
				</Text>
			</Group>

			<TransportControls playing={snapshot.playing} run={run} />

			<BottomControls
				snapshot={snapshot}
				run={run}
				displayTime={displayTime}
				duration={duration}
				setSeekPreview={setSeekPreview}
				onFullscreen={onFullscreen}
			/>
		</section>
	);
}

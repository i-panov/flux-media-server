import { ActionIcon, Group, Slider, Stack, Text } from "@mantine/core";
import {
	Maximize,
	Minimize,
	Pause,
	Play,
	RotateCcw,
	RotateCw,
	Volume2,
	VolumeX,
} from "lucide-react";
import {
	type KeyboardEvent as ReactKeyboardEvent,
	useEffect,
	useRef,
} from "react";
import { useTranslation } from "react-i18next";
import { formatDuration } from "../../core/format";
import {
	changeVideoVolume,
	seekVideoBy,
	TV_SEEK_STEP,
	toggleVideoMute,
	toggleVideoPlayback,
} from "../player/tvPlayerRemote";
import { clickNode, useTVFocusable } from "../tv/tvFocus";

export interface VideoSnapshot {
	playing: boolean;
	currentTime: number;
	duration: number;
	volume: number;
	muted: boolean;
	fullscreen: boolean;
	fullscreenAvailable: boolean;
}

export type RunVideoAction = (
	action: (video: HTMLVideoElement) => void,
) => void;

// Вертикальные стрелки на слайдере уходят в spatial: иначе фокус
// навсегда остаётся на слайдере. Горизонтальные — нативное значение.
const sliderArrowPress = (direction: string) =>
	direction === "up" || direction === "down";

// Кнопки транспорта: каждая — spatial-цель пульта. С play ←/→ заняты
// глобальным seek, ↑/↓ уходят в spatial; остальные кнопки листаются
// стрелками как обычные focusable-цели.
export function TransportControls({
	playing,
	run,
}: {
	playing: boolean;
	run: RunVideoAction;
}) {
	const { t } = useTranslation();
	const { targetRef: seekBackRef } = useTVFocusable<HTMLButtonElement>(
		"video-osd-seek-back",
		clickNode,
		undefined,
		{ secondary: true },
	);
	// С play ←/→ — глобальный seek, ↑/↓ отдаём spatial: иначе пульт
	// навсегда застревал бы на play и остальные кнопки/страница были
	// недостижимы. Enter/Space кликают play через clickNode.
	const playArrowPress = (direction: string) =>
		direction === "up" || direction === "down";
	const { targetRef: playRef } = useTVFocusable<HTMLButtonElement>(
		"video-osd-play",
		clickNode,
		playArrowPress,
	);
	const { targetRef: seekForwardRef } = useTVFocusable<HTMLButtonElement>(
		"video-osd-seek-forward",
		clickNode,
		undefined,
		{ secondary: true },
	);
	return (
		<Group
			gap="xl"
			justify="center"
			className="tv-video-osd__center"
			role="toolbar"
			aria-label={t("video.osd.transport")}
		>
			<ActionIcon
				variant="subtle"
				color="gray"
				c="white"
				size={56}
				radius="xl"
				ref={seekBackRef}
				aria-label={t("video.osd.seekBack")}
				onClick={() => run((video) => seekVideoBy(video, -TV_SEEK_STEP))}
			>
				<RotateCcw size={28} />
			</ActionIcon>
			<ActionIcon
				variant="white"
				color="violet"
				size={72}
				radius="xl"
				ref={playRef}
				aria-label={playing ? t("video.osd.pause") : t("video.osd.play")}
				data-testid={playing ? "tv-video-pause" : "tv-video-play"}
				onClick={() => run(toggleVideoPlayback)}
			>
				{playing ? <Pause size={34} /> : <Play size={34} fill="currentColor" />}
			</ActionIcon>
			<ActionIcon
				variant="subtle"
				color="gray"
				c="white"
				size={56}
				radius="xl"
				ref={seekForwardRef}
				aria-label={t("video.osd.seekForward")}
				onClick={() => run((video) => seekVideoBy(video, TV_SEEK_STEP))}
			>
				<RotateCw size={28} />
			</ActionIcon>
		</Group>
	);
}

export function BottomControls({
	snapshot,
	run,
	displayTime,
	duration,
	setSeekPreview,
	onFullscreen,
}: {
	snapshot: VideoSnapshot;
	run: RunVideoAction;
	displayTime: number;
	duration: number;
	setSeekPreview: (value: number | null) => void;
	onFullscreen: () => void;
}) {
	const { t } = useTranslation();
	const { targetRef: muteRef } = useTVFocusable<HTMLButtonElement>(
		"video-osd-mute",
		clickNode,
	);
	const { targetRef: fullscreenRef } = useTVFocusable<HTMLButtonElement>(
		"video-osd-fullscreen",
		clickNode,
	);
	// Слайдеры сами обрабатывают ←/→; ↑/↓ уходят в spatial.
	const { targetRef: timelineRef } = useTVFocusable<HTMLDivElement>(
		"video-osd-timeline",
		undefined,
		sliderArrowPress,
	);
	const { targetRef: volumeRef } = useTVFocusable<HTMLDivElement>(
		"video-osd-volume",
		undefined,
		sliderArrowPress,
	);
	const sliderVerticalKey = useRef(false);
	// keyup может уйти на уже другую spatial-цель, поэтому сбрасываем
	// флаг ещё и на window keyup/pointerdown — иначе seek/volume мышью
	// навсегда блокируются после вертикального ухода со слайдера.
	useEffect(() => {
		const reset = () => {
			sliderVerticalKey.current = false;
		};
		const onKeyUp = (event: KeyboardEvent) => {
			if (event.key === "ArrowUp" || event.key === "ArrowDown") {
				reset();
			}
		};
		window.addEventListener("keyup", onKeyUp, true);
		window.addEventListener("pointerdown", reset, true);
		return () => {
			window.removeEventListener("keyup", onKeyUp, true);
			window.removeEventListener("pointerdown", reset, true);
		};
	}, []);
	const onSliderKeyDownCapture = (
		event: ReactKeyboardEvent<HTMLDivElement>,
	) => {
		sliderVerticalKey.current =
			event.key === "ArrowUp" || event.key === "ArrowDown";
	};
	const onSliderKeyUpCapture = (event: ReactKeyboardEvent<HTMLDivElement>) => {
		if (event.key === "ArrowUp" || event.key === "ArrowDown") {
			sliderVerticalKey.current = false;
		}
	};
	const muted = snapshot.muted || snapshot.volume === 0;

	return (
		<Stack gap="xs" className="tv-video-osd__bottom">
			<div
				className="tv-video-osd__timeline"
				onKeyDownCapture={onSliderKeyDownCapture}
				onKeyUpCapture={onSliderKeyUpCapture}
			>
				<Slider
					value={Math.min(displayTime, duration)}
					min={0}
					max={duration}
					step={1}
					label={formatDuration(displayTime)}
					thumbLabel={t("video.osd.timeline")}
					thumbProps={{ ref: timelineRef }}
					color="violet"
					size="md"
					onChange={(value) => {
						if (!sliderVerticalKey.current) {
							setSeekPreview(value);
						}
					}}
					onChangeEnd={(value) => {
						if (sliderVerticalKey.current) {
							sliderVerticalKey.current = false;
							setSeekPreview(null);
							return;
						}
						run((video) => {
							video.currentTime = value;
						});
						setSeekPreview(null);
					}}
				/>
			</div>
			<Group justify="space-between" align="center" wrap="nowrap">
				<Text size="sm" className="tv-video-osd__time">
					{formatDuration(displayTime)} / {formatDuration(snapshot.duration)}
				</Text>
				<Group gap="sm" align="center" wrap="nowrap">
					<ActionIcon
						variant="subtle"
						color="gray"
						c="white"
						size="lg"
						radius="xl"
						ref={muteRef}
						aria-label={t("video.osd.mute")}
						aria-pressed={muted}
						onClick={() => run(toggleVideoMute)}
					>
						{muted ? <VolumeX size={22} /> : <Volume2 size={22} />}
					</ActionIcon>
					<div
						className="tv-video-osd__volume"
						onKeyDownCapture={onSliderKeyDownCapture}
						onKeyUpCapture={onSliderKeyUpCapture}
					>
						<Slider
							value={Math.round(snapshot.volume * 100)}
							min={0}
							max={100}
							step={1}
							label={`${Math.round(snapshot.volume * 100)}%`}
							thumbLabel={t("video.osd.volume")}
							thumbProps={{ ref: volumeRef }}
							color="violet"
							size="sm"
							onChange={(value) => {
								if (sliderVerticalKey.current) {
									sliderVerticalKey.current = false;
									return;
								}
								run((video) =>
									changeVideoVolume(video, value / 100 - video.volume),
								);
							}}
						/>
					</div>
					{snapshot.fullscreenAvailable && (
						<ActionIcon
							variant="subtle"
							color="gray"
							c="white"
							size="lg"
							radius="xl"
							ref={fullscreenRef}
							aria-label={
								snapshot.fullscreen
									? t("video.osd.exitFullscreen")
									: t("video.osd.fullscreen")
							}
							onClick={onFullscreen}
						>
							{snapshot.fullscreen ? (
								<Minimize size={22} />
							) : (
								<Maximize size={22} />
							)}
						</ActionIcon>
					)}
				</Group>
			</Group>
		</Stack>
	);
}

import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { useEvent, useEventListener } from "expo";
import { useKeepAwake } from "expo-keep-awake";
import {
	isPictureInPictureSupported,
	useVideoPlayer,
	VideoView,
} from "expo-video";
import { useCallback, useRef, useState } from "react";
import {
	ActivityIndicator,
	Alert,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { PlayerControls } from "./PlayerControls";
import { useVideoProgress } from "./useVideoProgress";
import { useVideoSource } from "./useVideoSource";
import { VideoPoster } from "./VideoPoster";
import {
	clampSeek,
	nextPlaybackRate,
	seekPlayer,
	updatePlaybackRate,
} from "./videoControls";

// Полсекунды — компромисс: таймлайн не дёргается, но seek виден сразу.
const TIME_UPDATE_INTERVAL_SECONDS = 0.5;
const KEEP_AWAKE_TAG = "flux-video-player";

interface VideoPlayerProps {
	media: Media;
	title?: string;
}

// Отдельный компонент, потому что useKeepAwake нельзя вызывать условно:
// он живёт ровно столько, сколько длится воспроизведение.
function AwakeWhilePlaying() {
	useKeepAwake(KEEP_AWAKE_TAG);
	return null;
}

// Центральный оверлей гейтится по hasStarted, а не по firstFrame: кадр может
// отрисоваться до нажатия Play, и кнопка не должна из-за этого исчезать.
function PlayOverlay({
	sourceReady,
	onPlay,
}: {
	sourceReady: boolean;
	onPlay: () => void;
}) {
	const { colors } = useTheme();
	if (!sourceReady) {
		return (
			<View style={styles.overlay}>
				<View style={[styles.playCircle, { backgroundColor: colors.overlay }]}>
					<ActivityIndicator
						accessibilityLabel={t("common.loading")}
						accessibilityLiveRegion="polite"
						accessibilityRole="progressbar"
						color={colors.onOverlay}
					/>
				</View>
			</View>
		);
	}
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={t("video.player.play")}
			onPress={onPlay}
			testID="video-player-play-overlay"
			style={styles.overlay}
		>
			<View style={[styles.playCircle, { backgroundColor: colors.overlay }]}>
				<Ionicons name="play" size={34} color={colors.onOverlay} />
			</View>
		</Pressable>
	);
}

function ErrorOverlay({ onRetry }: { onRetry: () => void }) {
	const { colors, radii, spacing } = useTheme();
	return (
		<View
			testID="video-player-error"
			style={[
				styles.overlay,
				{
					backgroundColor: colors.overlay,
					gap: spacing.sm,
					padding: spacing.lg,
				},
			]}
		>
			<Ionicons
				name="alert-circle-outline"
				size={32}
				color={colors.onOverlay}
			/>
			<Text
				accessibilityLabel={t("video.player.error")}
				accessibilityLiveRegion="assertive"
				style={[styles.errorText, { color: colors.onOverlay }]}
			>
				{t("video.player.error")}
			</Text>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.retry")}
				onPress={onRetry}
				testID="video-player-error-retry"
				style={[
					styles.retry,
					{ borderColor: colors.onOverlay, borderRadius: radii.pill },
				]}
			>
				<Text style={[styles.retryLabel, { color: colors.onOverlay }]}>
					{t("common.retry")}
				</Text>
			</Pressable>
		</View>
	);
}

export function VideoPlayer({ media, title }: VideoPlayerProps) {
	useLanguage();
	const { colors, radii } = useTheme();
	const viewRef = useRef<VideoView | null>(null);
	const [position, setPosition] = useState(0);
	const [duration, setDuration] = useState(0);
	const [rate, setRate] = useState(1);
	const [firstFrame, setFirstFrame] = useState(false);
	const [hasStarted, setHasStarted] = useState(false);
	const [recoveredFromError, setRecoveredFromError] = useState(false);
	const [pipSupported] = useState(isPictureInPictureSupported);

	const player = useVideoPlayer(null, (instance) => {
		instance.timeUpdateEventInterval = TIME_UPDATE_INTERVAL_SECONDS;
	});

	const { isPlaying } = useEvent(player, "playingChange", {
		isPlaying: player.playing,
	});

	const resetPlaybackState = useCallback(() => {
		setPosition(0);
		setDuration(0);
		setFirstFrame(false);
		setHasStarted(false);
	}, []);

	const handlePlaybackRestored = useCallback((playing: boolean) => {
		if (playing) {
			setHasStarted(true);
		}
	}, []);

	const handlePositionRestored = useCallback((seconds: number) => {
		// 401-ветка уже перемотала плеер на сохранённую позицию: серверный
		// resume поверх неё не должен спорить за ту же секунду. Нулевая
		// позиция — это не восстановление, resume с сервера уместен.
		setPosition(seconds);
		if (seconds > 0) {
			setRecoveredFromError(true);
		}
	}, []);

	// Источник/replaceAsync/401-ретрай вынесены в отдельный хук: компонент
	// отвечает только за UI и нативные контролы.
	const { sourceReady, failed, retry } = useVideoSource({
		mediaId: media.id,
		player,
		onSourceReset: resetPlaybackState,
		onPositionRestored: handlePositionRestored,
		onPlaybackRestored: handlePlaybackRestored,
	});

	// Серверный resume — только после готовности источника и только если
	// пользователь ещё не начал: 401-восстановление внутри useVideoSource
	// остаётся главным и здесь не дублируется.
	const {
		resumed,
		reset: resetProgress,
		handleSeek,
	} = useVideoProgress({
		mediaId: media.id,
		player,
		sourceReady,
		hasStarted,
		resumeDisabled: recoveredFromError,
		onPositionRestored: setPosition,
	});

	const resetPlayback = useCallback(() => {
		// Сначала пауза: playingChange не должен успеть сохранить старую
		// позицию после DELETE. Затем reset хука (seek 0 + DELETE + marker).
		player.pause();
		setHasStarted(false);
		setPosition(0);
		void resetProgress();
	}, [player, resetProgress]);

	useEventListener(player, "timeUpdate", ({ currentTime }) => {
		setPosition(currentTime);
	});

	useEventListener(player, "sourceLoad", ({ duration: loadedDuration }) => {
		if (Number.isFinite(loadedDuration) && loadedDuration > 0) {
			setDuration(loadedDuration);
		}
	});

	// Нативная панель/fullscreen могут сменить скорость в обход кнопки:
	// состояние должно следовать за плеером, а не только за нашими нажатиями.
	useEventListener(player, "playbackRateChange", ({ playbackRate }) => {
		if (Number.isFinite(playbackRate) && playbackRate > 0) {
			setRate(playbackRate);
		}
	});

	useEventListener(player, "playingChange", ({ isPlaying: playing }) => {
		if (playing) {
			setHasStarted(true);
		}
	});

	useEventListener(player, "playToEnd", () => {
		// play() в конце может быть no-op: возвращаем позицию в 0, чтобы Play
		// перезапускал видео с начала.
		seekPlayer(player, 0);
		setPosition(0);
	});

	const aspectRatio =
		media.width > 0 && media.height > 0 ? media.width / media.height : 16 / 9;

	const seekTo = (seconds: number) => {
		const next = clampSeek(seconds, 0, duration);
		seekPlayer(player, next);
		setPosition(next);
		// Ручной возврат в 0 после playback удаляет серверный прогресс.
		handleSeek(next);
	};

	const startPlayback = () => {
		setHasStarted(true);
		player.play();
	};

	const togglePlayback = () => {
		if (player.playing) {
			player.pause();
		} else {
			startPlayback();
		}
	};

	const cycleRate = () => {
		const next = nextPlaybackRate(rate);
		updatePlaybackRate(player, next, player.playing);
		setRate(next);
	};

	const enterFullscreen = () => {
		viewRef.current?.enterFullscreen().catch(() => {
			Alert.alert(t("video.player.fullscreenError"));
		});
	};

	const startPictureInPicture = () => {
		viewRef.current?.startPictureInPicture().catch(() => {
			Alert.alert(t("video.player.pipError"));
		});
	};

	return (
		<View
			testID="video-player"
			style={[
				styles.container,
				// Плеерная подложка всегда тёмная: на ней белые подписи и иконки
				// onOverlay, поэтому полупрозрачный overlay на светлой теме не
				// годится (давал серый фон и контраст около 1:1).
				{ backgroundColor: colors.playerChrome, borderRadius: radii.md },
			]}
		>
			<View style={[styles.stage, { aspectRatio }]}>
				<VideoView
					ref={viewRef}
					player={player}
					style={StyleSheet.absoluteFill}
					nativeControls={false}
					contentFit="contain"
					allowsPictureInPicture={pipSupported}
					fullscreenOptions={{ enable: true, orientation: "landscape" }}
					accessibilityLabel={title ?? media.title}
					onFirstFrameRender={() => setFirstFrame(true)}
				/>
				{!firstFrame && !failed && <VideoPoster key={media.id} media={media} />}
				{!hasStarted && !failed && (
					<PlayOverlay sourceReady={sourceReady} onPlay={startPlayback} />
				)}
				{failed && <ErrorOverlay onRetry={retry} />}
				{/* Маленький неинтерактивный probe для Maestro: состояние playback. */}
				<Text
					testID="video-player-state"
					accessible={false}
					pointerEvents="none"
					style={[
						styles.stateProbe,
						{
							backgroundColor: colors.playerChrome,
							color: colors.playerChrome,
						},
					]}
				>
					{isPlaying ? "playing" : "paused"}
				</Text>
				{/* Маркер для Maestro: resume применён (время читать неудобно). */}
				{resumed && (
					<Text
						testID="video-player-resumed"
						accessible={false}
						pointerEvents="none"
						style={[
							styles.stateProbe,
							{
								backgroundColor: colors.playerChrome,
								color: colors.playerChrome,
							},
						]}
					>
						resumed
					</Text>
				)}
			</View>
			{!failed && (
				<PlayerControls
					position={position}
					duration={duration}
					isPlaying={isPlaying}
					rate={rate}
					pipSupported={pipSupported}
					onSeekTo={seekTo}
					onTogglePlayback={togglePlayback}
					onReset={resetPlayback}
					onCycleRate={cycleRate}
					onFullscreen={enterFullscreen}
					onPictureInPicture={startPictureInPicture}
				/>
			)}
			{isPlaying && <AwakeWhilePlaying />}
		</View>
	);
}

const styles = StyleSheet.create({
	container: { width: "100%", overflow: "hidden" },
	stage: { width: "100%" },
	overlay: {
		position: "absolute",
		top: 0,
		right: 0,
		bottom: 0,
		left: 0,
		alignItems: "center",
		justifyContent: "center",
	},
	playCircle: {
		width: 72,
		height: 72,
		borderRadius: 36,
		alignItems: "center",
		justifyContent: "center",
	},
	errorText: { fontSize: 15, fontWeight: "600", textAlign: "center" },
	retry: {
		minHeight: 44,
		paddingHorizontal: 18,
		alignItems: "center",
		justifyContent: "center",
		borderWidth: 1,
	},
	retryLabel: { fontSize: 14, fontWeight: "600" },
	stateProbe: {
		position: "absolute",
		width: 1,
		height: 1,
		fontSize: 1,
	},
});

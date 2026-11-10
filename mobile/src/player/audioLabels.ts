import { formatDuration, type RepeatMode } from "@flux/shared";
import { t } from "../i18n";

// Шаг seek-кнопок и accessibilityActions, общий для таймлайна и контролов.
export const SEEK_STEP_SECONDS = 10;

// formatDuration не рассчитан на NaN/Infinity от ещё не загруженного плеера.
export function formatAudioTime(seconds: number): string {
	if (!Number.isFinite(seconds) || seconds < 0) {
		return "0:00";
	}
	return formatDuration(seconds);
}

export function seekLabel(delta: number): string {
	return t(
		delta < 0 ? "audio.player.seekBackward" : "audio.player.seekForward",
		{ seconds: Math.abs(delta) },
	);
}

export function repeatLabel(repeat: RepeatMode): string {
	switch (repeat) {
		case "all":
			return t("audio.player.repeatAll");
		case "one":
			return t("audio.player.repeatOne");
		default:
			return t("audio.player.repeatOff");
	}
}

import type { ExtractFailure, ExtractPhase } from "../api/extract";
import { t } from "../i18n";

// Подписи фаз и ошибок извлечения: вынесены из экрана видео, чтобы он
// оставался в пределах лимита размера файла.
export function extractPhaseLabel(phase: ExtractPhase | null): string {
	if (phase === "processing") {
		return t("video.extractProcessing");
	}
	if (phase === "queued") {
		return t("video.extractQueued");
	}
	return t("video.extractStarting");
}

export function extractFailureLabel(failure: ExtractFailure): string {
	switch (failure.kind) {
		case "conflict":
			return t("video.extractAlready");
		case "unavailable":
			return t("video.extractUnavailable");
		case "rateLimited":
			return t("video.extractRateLimited");
		default:
			return t("video.extractError");
	}
}

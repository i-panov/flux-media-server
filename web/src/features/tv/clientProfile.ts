// Чистая эвристика клиента: ТВ определяется по совокупности сигналов,
// а не по одному User-Agent. Явные `?tv=1`/`?tv=0` и ручной тумблер
// решаются выше, в TVModeContext; здесь только автоопределение.

type ClientKind = "desktop" | "mobile" | "tv";

export interface ClientProfileInput {
	userAgent: string;
	// Платформенные API: window.tizen/webOS/VIDAA/hbbtv.
	tizen?: boolean;
	webOS?: boolean;
	vidaa?: boolean;
	hbbtv?: boolean;
	// matchMedia('(hover: none) and (pointer: none)') — типично для ТВ.
	hoverNone?: boolean;
	// matchMedia('(pointer: coarse)') — типично для тач-устройств.
	pointerCoarse?: boolean;
	maxTouchPoints?: number;
	screenWidth?: number;
	screenHeight?: number;
	outerWidth?: number;
	outerHeight?: number;
}

export interface ClientProfile {
	kind: ClientKind;
	isTV: boolean;
	isMobile: boolean;
	// Сигналы есть, но их недостаточно для ТВ: обычный режим + подсказка.
	ambiguous: boolean;
	score: number;
	signals: string[];
}

// UA-маркеры ТВ-платформ. AFT — семейство Fire TV, CrKey — Chromecast.
const TV_UA_PATTERN =
	/SmartTV|Tizen|Web0S|webOS|HbbTV|NetCast|BRAVIA|Android TV|GoogleTV|Google TV|FireTV|Fire TV|AFT|VIDAA|Hisense|Philips|Opera TV|Roku|CrKey/i;
const MOBILE_UA_PATTERN = /Mobi|Android|iPhone|iPad|iPod/i;

const TV_SCORE_THRESHOLD = 5;
const AMBIGUOUS_SCORE_THRESHOLD = 4;

function positive(value: number | undefined): number {
	return typeof value === "number" && Number.isFinite(value) && value > 0
		? value
		: 0;
}

// Чистая функция без доступа к window: удобно тестировать и переиспользовать.
export function detectClientProfile(input: ClientProfileInput): ClientProfile {
	let score = 0;
	const signals: string[] = [];

	if (TV_UA_PATTERN.test(input.userAgent)) {
		score += 5;
		signals.push("ua");
	}
	if (input.tizen === true) {
		score += 5;
		signals.push("tizen");
	}
	if (input.webOS === true) {
		score += 5;
		signals.push("webos");
	}
	if (input.vidaa === true) {
		score += 5;
		signals.push("vidaa");
	}
	if (input.hbbtv === true) {
		score += 5;
		signals.push("hbbtv");
	}
	// ТВ обычно без hover и без точного указателя. Это сильный, но не
	// решающий сигнал: hover:none/pointer:none бывает и в киосках.
	if (input.hoverNone === true) {
		score += 3;
		signals.push("hover-none");
	}
	if (input.pointerCoarse === true) {
		score += 1;
		signals.push("pointer-coarse");
	}
	if (input.maxTouchPoints === 0) {
		score += 1;
		signals.push("no-touch");
	}

	// Слабые сигналы: большой экран и полноэкранное окно. Сами по себе
	// ТВ не включают, но подтверждают UA/платформенные признаки.
	const screenWidth = positive(input.screenWidth);
	const screenHeight = positive(input.screenHeight);
	const outerWidth = positive(input.outerWidth);
	const outerHeight = positive(input.outerHeight);
	if (screenWidth >= 1920 && screenHeight >= 1080) {
		score += 1;
		signals.push("big-screen");
	}
	if (
		outerWidth > 0 &&
		outerHeight > 0 &&
		outerWidth >= screenWidth &&
		outerHeight >= screenHeight
	) {
		score += 1;
		signals.push("fullscreen-window");
	}

	const isTV = score >= TV_SCORE_THRESHOLD;
	const isMobile =
		!isTV &&
		(MOBILE_UA_PATTERN.test(input.userAgent) ||
			(input.pointerCoarse === true && (input.maxTouchPoints ?? 0) > 0));
	// Неоднозначно: сигналы ТВ есть, но порог не пройден. Мобильные
	// устройства не получают подсказку — у них своя навигация.
	const ambiguous = !isTV && !isMobile && score >= AMBIGUOUS_SCORE_THRESHOLD;

	return {
		kind: isTV ? "tv" : isMobile ? "mobile" : "desktop",
		isTV,
		isMobile,
		ambiguous,
		score,
		signals,
	};
}

function safeMatchMedia(query: string): boolean {
	try {
		return window.matchMedia(query).matches;
	} catch {
		return false;
	}
}

function readPositive(value: number): number {
	return Number.isFinite(value) && value > 0 ? value : 0;
}

function hasPlatformApi(value: unknown): boolean {
	return value !== undefined && value !== null;
}

// Снимок реального окружения. Ошибки платформенных API (приватный режим,
// старый WebKit) не должны ломать загрузку приложения.
export function detectBrowserClientProfile(): ClientProfile {
	if (typeof window === "undefined") {
		return detectClientProfile({ userAgent: "" });
	}
	const platform = window as Window & {
		tizen?: unknown;
		webOS?: unknown;
		VIDAA?: unknown;
		hbbtv?: unknown;
	};
	return detectClientProfile({
		userAgent: navigator.userAgent,
		tizen: hasPlatformApi(platform.tizen),
		webOS: hasPlatformApi(platform.webOS),
		vidaa: hasPlatformApi(platform.VIDAA),
		hbbtv: hasPlatformApi(platform.hbbtv),
		hoverNone: safeMatchMedia("(hover: none) and (pointer: none)"),
		pointerCoarse: safeMatchMedia("(pointer: coarse)"),
		maxTouchPoints: readPositive(navigator.maxTouchPoints),
		screenWidth: readPositive(window.screen?.width ?? 0),
		screenHeight: readPositive(window.screen?.height ?? 0),
		outerWidth: readPositive(window.outerWidth),
		outerHeight: readPositive(window.outerHeight),
	});
}

// Приоритет: URL-параметр, затем сохранённый явный выбор, затем автоопределение.
export function resolveTVMode(
	param: boolean | null,
	stored: boolean | null,
	profile: ClientProfile,
): boolean {
	if (param !== null) {
		return param;
	}
	if (stored !== null) {
		return stored;
	}
	return profile.isTV;
}

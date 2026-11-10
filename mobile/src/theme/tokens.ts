// Токены темы: единственный источник цветов, отступов и радиусов.
// Модуль намеренно не зависит от React Native, чтобы чистые функции
// (resolveTheme/parseThemeMode) тестировались в Node без нативного рантайма.

export const THEME_STORAGE_KEY = "flux.theme";

export const THEME_MODES = ["system", "light", "dark"] as const;

export type ThemeMode = (typeof THEME_MODES)[number];

export type ResolvedTheme = "light" | "dark";

// useColorScheme() на RN возвращает "light" | "dark" | null | undefined.
export type SystemColorScheme = ResolvedTheme | null | undefined;

export function resolveTheme(
	mode: ThemeMode,
	system: SystemColorScheme,
): ResolvedTheme {
	if (mode === "system") {
		return system === "dark" ? "dark" : "light";
	}
	return mode;
}

export function parseThemeMode(value: string | null | undefined): ThemeMode {
	switch (value) {
		case "light":
		case "dark":
		case "system":
			return value;
		default:
			return "system";
	}
}

export interface ThemeColors {
	readonly background: string;
	readonly surface: string;
	readonly surfaceMuted: string;
	readonly text: string;
	readonly textMuted: string;
	readonly accent: string;
	readonly onAccent: string;
	readonly border: string;
	readonly borderStrong: string;
	/** Рамка полей ввода: контраст ≥3:1 к surface/background. */
	readonly controlBorder: string;
	readonly danger: string;
	readonly overlay: string;
	readonly onOverlay: string;
	/**
	 * Подложка плеера: всегда тёмная, независимо от темы, потому что поверх
	 * неё лежат белые иконки/подписи onOverlay. Полупрозрачный overlay здесь
	 * не подходит — на светлой теме он давал серый фон с контрастом ~1:1.
	 */
	readonly playerChrome: string;
	/** Незаполненная часть таймлайна на playerChrome (декоративная). */
	readonly playerTrack: string;
	readonly favorite: string;
}

export const spacing = {
	xs: 4,
	sm: 8,
	md: 12,
	lg: 16,
	xl: 24,
	xxl: 32,
} as const;

export const radii = {
	sm: 8,
	md: 12,
	lg: 16,
	pill: 999,
} as const;

export const lightColors: ThemeColors = {
	background: "#ffffff",
	surface: "#f8f9fa",
	surfaceMuted: "#e9ecef",
	text: "#212529",
	textMuted: "#5c636a",
	accent: "#6741d9",
	onAccent: "#ffffff",
	border: "#dee2e6",
	borderStrong: "#adb5bd",
	controlBorder: "#6c757d",
	danger: "#c92a2a",
	overlay: "rgba(0, 0, 0, 0.6)",
	onOverlay: "#ffffff",
	playerChrome: "#000000",
	playerTrack: "rgba(255, 255, 255, 0.3)",
	favorite: "#c92a2a",
};

export const darkColors: ThemeColors = {
	background: "#141517",
	surface: "#1f2124",
	surfaceMuted: "#2b2d31",
	text: "#f1f3f5",
	textMuted: "#a6a7ab",
	accent: "#9775fa",
	onAccent: "#141517",
	border: "#34363b",
	borderStrong: "#4b4f56",
	controlBorder: "#8c939c",
	danger: "#ff6b6b",
	overlay: "rgba(0, 0, 0, 0.6)",
	onOverlay: "#ffffff",
	playerChrome: "#000000",
	playerTrack: "rgba(255, 255, 255, 0.3)",
	favorite: "#c92a2a",
};

export interface ThemeTokens {
	readonly scheme: ResolvedTheme;
	readonly colors: ThemeColors;
	readonly spacing: typeof spacing;
	readonly radii: typeof radii;
}

export function getThemeTokens(scheme: ResolvedTheme): ThemeTokens {
	return {
		scheme,
		colors: scheme === "dark" ? darkColors : lightColors,
		spacing,
		radii,
	};
}

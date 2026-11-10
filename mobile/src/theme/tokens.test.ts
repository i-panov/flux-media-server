import { describe, expect, it } from "vitest";
import {
	getThemeTokens,
	parseThemeMode,
	resolveTheme,
	THEME_STORAGE_KEY,
	type ThemeColors,
} from "./tokens";

function channel(value: number): number {
	const normalized = value / 255;
	return normalized <= 0.04045
		? normalized / 12.92
		: ((normalized + 0.055) / 1.055) ** 2.4;
}

function luminance(hex: string): number {
	const [red, green, blue] = [1, 3, 5].map((offset) =>
		channel(Number.parseInt(hex.slice(offset, offset + 2), 16)),
	);
	return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function contrastRatio(foreground: string, background: string): number {
	const a = luminance(foreground);
	const b = luminance(background);
	return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

const RGBA_PATTERN = /^rgba?\(([^)]+)\)$/;

function parseColor(value: string): [number, number, number, number] {
	if (value.startsWith("#")) {
		return [
			Number.parseInt(value.slice(1, 3), 16),
			Number.parseInt(value.slice(3, 5), 16),
			Number.parseInt(value.slice(5, 7), 16),
			1,
		];
	}
	const parts = RGBA_PATTERN.exec(value)?.[1]
		.split(",")
		.map((part) => Number.parseFloat(part.trim()));
	if (parts === undefined || parts.length < 3) {
		throw new Error(`Unsupported color: ${value}`);
	}
	return [parts[0], parts[1], parts[2], parts[3] ?? 1];
}

// Композит полупрозрачного цвета поверх непрозрачного фона → hex для
// переиспользования contrastRatio.
function compositeOver(foreground: string, background: string): string {
	const [fr, fg, fb, fa] = parseColor(foreground);
	const [br, bg, bb] = parseColor(background);
	const blend = (front: number, back: number) =>
		Math.round(front * fa + back * (1 - fa));
	return `#${[blend(fr, br), blend(fg, bg), blend(fb, bb)]
		.map((channel) => channel.toString(16).padStart(2, "0"))
		.join("")}`;
}

describe("mobile theme", () => {
	it("resolveTheme учитывает явный выбор и системную схему", () => {
		expect(resolveTheme("light", "dark")).toBe("light");
		expect(resolveTheme("dark", "light")).toBe("dark");
		expect(resolveTheme("system", "dark")).toBe("dark");
		expect(resolveTheme("system", "light")).toBe("light");
		// useColorScheme() может вернуть null/undefined до готовности ОС.
		expect(resolveTheme("system", null)).toBe("light");
		expect(resolveTheme("system", undefined)).toBe("light");
	});

	it("parseThemeMode принимает только сохранённые значения", () => {
		expect(parseThemeMode("system")).toBe("system");
		expect(parseThemeMode("light")).toBe("light");
		expect(parseThemeMode("dark")).toBe("dark");
		expect(parseThemeMode("sepia")).toBe("system");
		expect(parseThemeMode("")).toBe("system");
		expect(parseThemeMode(null)).toBe("system");
		expect(parseThemeMode(undefined)).toBe("system");
	});

	it("отдаёт разные палитры при общей шкале отступов", () => {
		expect(THEME_STORAGE_KEY).toBe("flux.theme");
		const light = getThemeTokens("light");
		const dark = getThemeTokens("dark");
		expect(light.scheme).toBe("light");
		expect(dark.scheme).toBe("dark");
		expect(light.colors.background).not.toBe(dark.colors.background);
		expect(light.colors.text).not.toBe(dark.colors.text);
		expect(light.spacing).toBe(dark.spacing);
		expect(light.radii.md).toBeGreaterThan(0);
	});

	it("controlBorder имеет контраст ≥3:1 к полю и фону в обеих темах", () => {
		const themes: ThemeColors[] = [
			getThemeTokens("light").colors,
			getThemeTokens("dark").colors,
		];
		for (const colors of themes) {
			expect(
				contrastRatio(colors.controlBorder, colors.surface),
			).toBeGreaterThanOrEqual(3);
			expect(
				contrastRatio(colors.controlBorder, colors.background),
			).toBeGreaterThanOrEqual(3);
		}
	});

	it("заливка таймлайна контрастирует с треком в обеих темах", () => {
		const themes: ThemeColors[] = [
			getThemeTokens("light").colors,
			getThemeTokens("dark").colors,
		];
		for (const colors of themes) {
			const track = compositeOver(colors.playerTrack, colors.playerChrome);
			expect(contrastRatio(colors.onOverlay, track)).toBeGreaterThanOrEqual(3);
		}
	});

	it("playerChrome тёмный и контрастирует с onOverlay в обеих темах", () => {
		const themes: ThemeColors[] = [
			getThemeTokens("light").colors,
			getThemeTokens("dark").colors,
		];
		for (const colors of themes) {
			// Плеерная подложка не зависит от темы: поверх неё всегда белые
			// подписи/иконки, поэтому контраст должен быть высоким.
			expect(
				contrastRatio(colors.onOverlay, colors.playerChrome),
			).toBeGreaterThanOrEqual(7);
		}
	});
});

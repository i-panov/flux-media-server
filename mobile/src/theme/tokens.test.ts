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
});

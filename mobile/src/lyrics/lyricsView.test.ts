import { describe, expect, it } from "vitest";
import {
	defaultLyricsTab,
	hasLyricsContent,
	hasLyricsText,
	hasTranslation,
	highlightLineIndex,
	parseMediaIdParam,
	resolveLyricsTab,
	syncedLines,
} from "./lyricsView";

describe("вкладки текста и перевода", () => {
	it("пустой и пробельный перевод не считается переводом", () => {
		expect(hasTranslation("")).toBe(false);
		expect(hasTranslation("   \n ")).toBe(false);
		expect(hasTranslation("Перевод")).toBe(true);
	});

	it("скрытый перевод переключает активную вкладку на текст", () => {
		expect(resolveLyricsTab("translation", "")).toBe("lyrics");
		expect(resolveLyricsTab("translation", "   ")).toBe("lyrics");
	});

	it("существующий перевод оставляет вкладку перевода", () => {
		expect(resolveLyricsTab("translation", "Перевод")).toBe("translation");
		expect(resolveLyricsTab("lyrics", "Перевод")).toBe("lyrics");
	});

	it("без текста, но с переводом стартует вкладка перевода", () => {
		expect(defaultLyricsTab(false, "Перевод")).toBe("translation");
		expect(defaultLyricsTab(true, "Перевод")).toBe("lyrics");
		expect(defaultLyricsTab(false, "")).toBe("lyrics");
	});
});

describe("пустой текст", () => {
	it("запись из пустых/пробельных полей считается отсутствующей", () => {
		expect(hasLyricsContent(null)).toBe(false);
		expect(
			hasLyricsContent({ lyrics_text: "", translation: " ", sync_data: "\n" }),
		).toBe(false);
		expect(
			hasLyricsContent({
				lyrics_text: "Текст",
				translation: "",
				sync_data: "",
			}),
		).toBe(true);
		expect(
			hasLyricsContent({
				lyrics_text: "",
				translation: "Перевод",
				sync_data: "",
			}),
		).toBe(true);
	});

	it("LRC-строки считаются текстом для стартовой вкладки", () => {
		expect(hasLyricsText("", "[00:01.00] Строка")).toBe(true);
		expect(hasLyricsText("   ", "")).toBe(false);
	});
});

// biome-ignore lint/security/noSecrets: тестовые LRC-строки, не секрет.
const LRC = "[00:10.00] Первая\n[00:20.00] Вторая";

describe("подсветка строк", () => {
	it("для чужого трека позиция не подсвечивается", () => {
		const lines = syncedLines(LRC);
		expect(highlightLineIndex(lines, 25, false)).toBe(-1);
	});

	it("для играющего трека берётся последняя прошедшая строка", () => {
		const lines = syncedLines(LRC);
		expect(highlightLineIndex(lines, 5, true)).toBe(-1);
		expect(highlightLineIndex(lines, 10, true)).toBe(0);
		expect(highlightLineIndex(lines, 25, true)).toBe(1);
	});

	it("без sync_data подсветки нет", () => {
		expect(highlightLineIndex(syncedLines(""), 30, true)).toBe(-1);
	});
});

describe("id из маршрута", () => {
	it("принимает только положительное целое", () => {
		expect(parseMediaIdParam("42")).toBe(42);
		expect(parseMediaIdParam("0")).toBeNull();
		expect(parseMediaIdParam("-1")).toBeNull();
		expect(parseMediaIdParam("1.5")).toBeNull();
		expect(parseMediaIdParam("abc")).toBeNull();
		expect(parseMediaIdParam(" 5")).toBeNull();
		expect(parseMediaIdParam("1e2")).toBeNull();
		expect(parseMediaIdParam("0x10")).toBeNull();
		expect(parseMediaIdParam("+1")).toBeNull();
		expect(parseMediaIdParam(undefined)).toBeNull();
	});

	it("берёт первый элемент массива параметров", () => {
		expect(parseMediaIdParam(["7", "8"])).toBe(7);
	});
});

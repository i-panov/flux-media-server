import { describe, expect, it } from "vitest";
import { parseSyncedLyrics, syncedLyricIndex } from "./lyricsSync";

describe("parseSyncedLyrics", () => {
	it("разбирает таймкоды с долями секунд", () => {
		// biome-ignore lint/security/noSecrets: LRC-фикстура, а не секрет.
		const lines = parseSyncedLyrics("[00:01.50] Первая\n[01:02] Вторая");
		expect(lines).toEqual([
			{ time: 1.5, text: "Первая" },
			{ time: 62, text: "Вторая" },
		]);
	});

	it("разворачивает несколько таймкодов в строке", () => {
		const lines = parseSyncedLyrics("[00:10.00][00:20.00] Припев");
		expect(lines).toEqual([
			{ time: 10, text: "Припев" },
			{ time: 20, text: "Припев" },
		]);
	});

	it("пропускает пустые строки и строки без тегов", () => {
		const lines = parseSyncedLyrics("\nБез тега\n[00:05] Со тегом\n");
		expect(lines).toEqual([{ time: 5, text: "Со тегом" }]);
	});

	it("пустой ввод даёт пустой список", () => {
		expect(parseSyncedLyrics("")).toEqual([]);
	});
});

describe("syncedLyricIndex", () => {
	const lines = [
		{ time: 10, text: "Раз" },
		{ time: 20, text: "Два" },
	];

	it("до первой строки индекса нет", () => {
		expect(syncedLyricIndex(lines, 0)).toBe(-1);
		expect(syncedLyricIndex(lines, 9.9)).toBe(-1);
	});

	it("выбирает последнюю прошедшую строку", () => {
		expect(syncedLyricIndex(lines, 10)).toBe(0);
		expect(syncedLyricIndex(lines, 15)).toBe(0);
		expect(syncedLyricIndex(lines, 99)).toBe(1);
	});
});

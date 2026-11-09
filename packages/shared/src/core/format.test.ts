import { describe, expect, it } from "vitest";
import { formatDuration, parseFilename, splitSubLang } from "./format";

describe("formatDuration", () => {
	it("форматирует секунды и минуты без часов", () => {
		expect(formatDuration(0)).toBe("0:00");
		expect(formatDuration(5)).toBe("0:05");
		expect(formatDuration(65)).toBe("1:05");
	});

	it("добавляет часы с нулевым паддингом минут", () => {
		expect(formatDuration(3600)).toBe("1:00:00");
		expect(formatDuration(3725)).toBe("1:02:05");
	});

	it("отбрасывает дробь и clamp'ит отрицательные", () => {
		expect(formatDuration(90.9)).toBe("1:30");
		expect(formatDuration(-10)).toBe("0:00");
	});
});

describe("splitSubLang", () => {
	it("оставляет обычный язык как есть", () => {
		expect(splitSubLang("rus")).toEqual({ base: "rus", label: "rus" });
		expect(splitSubLang("en")).toEqual({ base: "en", label: "en" });
	});

	it("снимает суффикс дедупа, показывая номер в label", () => {
		expect(splitSubLang("rus2")).toEqual({ base: "rus", label: "rus (2)" });
		expect(splitSubLang("eng10")).toEqual({
			base: "eng",
			label: "eng (10)",
		});
	});

	it("не трогает числовые подтеги регионов и вариантов", () => {
		expect(splitSubLang("es-419")).toEqual({
			base: "es-419",
			label: "es-419",
		});
		expect(splitSubLang("en-001")).toEqual({
			base: "en-001",
			label: "en-001",
		});
		expect(splitSubLang("de-1996")).toEqual({
			base: "de-1996",
			label: "de-1996",
		});
	});

	it("неоднозначный хвост (регион или дедуп) оставляет как есть", () => {
		// es-4192: регион 4192 или дедуп es-419 — без бэкенд-метаданных
		// не различить, целый тег валиден и безопасен.
		expect(splitSubLang("es-4192")).toEqual({
			base: "es-4192",
			label: "es-4192",
		});
	});
});

describe("parseFilename", () => {
	it("разбирает Title.Year.ext", () => {
		expect(parseFilename("Matrix.1999.mkv")).toEqual({
			title: "Matrix",
			year: 1999,
		});
	});

	it("разбирает Title (Year).ext", () => {
		expect(parseFilename("Matrix (1999).mp4")).toEqual({
			title: "Matrix",
			year: 1999,
		});
	});

	it("разбирает Title.S01E05.ext без года", () => {
		expect(parseFilename("Show.S01E05.mkv")).toEqual({
			title: "Show",
			year: null,
		});
	});

	it("фолбэк: имя без расширения, точки в пробелы", () => {
		expect(parseFilename("My.Home.Video.mp4")).toEqual({
			title: "My Home Video",
			year: null,
		});
	});
});

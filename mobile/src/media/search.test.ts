import { describe, expect, it } from "vitest";
import { nextSort, normalizeSearchQuery } from "./search";

describe("normalizeSearchQuery", () => {
	it("режет пробелы по краям", () => {
		expect(normalizeSearchQuery("  dune  ")).toBe("dune");
		expect(normalizeSearchQuery("\n\tdune\r\n")).toBe("dune");
	});

	it("схлопывает внутренние пробелы и табы", () => {
		expect(normalizeSearchQuery("dune   part\t two")).toBe("dune part two");
	});

	it("пустой и пробельный запрос превращает в пустую строку", () => {
		expect(normalizeSearchQuery("")).toBe("");
		expect(normalizeSearchQuery("   \t\n ")).toBe("");
	});
});

describe("nextSort", () => {
	it("переключает desc → asc → desc", () => {
		expect(nextSort("desc")).toBe("asc");
		expect(nextSort("asc")).toBe("desc");
	});
});

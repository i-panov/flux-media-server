import { describe, expect, it } from "vitest";
import { catalogCardWidth, catalogColumns, catalogPadding } from "./grid";

describe("catalogColumns", () => {
	it("2 колонки на телефоне, 3 на планшете, 4 на широком", () => {
		expect(catalogColumns(360)).toBe(2);
		expect(catalogColumns(599)).toBe(2);
		expect(catalogColumns(600)).toBe(3);
		expect(catalogColumns(899)).toBe(3);
		expect(catalogColumns(900)).toBe(4);
	});
});

describe("catalogPadding", () => {
	it("на ТВ отступ больше", () => {
		const spacing = { lg: 16, xl: 24 };
		expect(catalogPadding(false, spacing)).toBe(16);
		expect(catalogPadding(true, spacing)).toBe(24);
	});
});

describe("catalogCardWidth", () => {
	it("делит ширину с учётом отступов и промежутков", () => {
		// 360 - 2*16 - 12 = 316; 316/2 = 158.
		expect(catalogCardWidth(360, 2, 16, 12)).toBe(158);
		expect(catalogCardWidth(900, 4, 24, 12)).toBe(204);
	});

	it("не отдаёт отрицательную ширину", () => {
		expect(catalogCardWidth(10, 4, 16, 12)).toBe(0);
	});
});

import { describe, expect, it } from "vitest";
import { mergeWorks, parseCatalogID } from "./catalogView";

describe("parseCatalogID", () => {
	it("принимает положительный integer", () => {
		expect(parseCatalogID("7")).toBe(7);
		expect(parseCatalogID("9007199254740991")).toBe(9007199254740991);
	});
	it("отвергает мусор и небезопасные значения", () => {
		for (const raw of [
			undefined,
			"",
			"0",
			"-1",
			"1e3",
			" 7",
			"7 ",
			"abc",
			"1.5",
			"9007199254740992",
		]) {
			expect(parseCatalogID(raw)).toBeNull();
		}
	});
});

describe("mergeWorks", () => {
	it("сохраняет порядок series → films и терпит undefined", () => {
		const series = [{ id: 1 }] as never;
		const films = [{ id: 2 }] as never;
		expect(mergeWorks(series, films).map((work) => work.id)).toEqual([1, 2]);
		expect(mergeWorks(undefined, undefined)).toEqual([]);
	});
});

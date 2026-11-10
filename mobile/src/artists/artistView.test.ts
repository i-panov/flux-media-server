import { describe, expect, it } from "vitest";
import { parseArtistIdParam } from "./artistView";

describe("parseArtistIdParam", () => {
	it("принимает положительный целый id", () => {
		expect(parseArtistIdParam("42")).toBe(42);
		expect(parseArtistIdParam(["7", "9"])).toBe(7);
	});

	it("отклоняет мусор и небезопасные значения", () => {
		expect(parseArtistIdParam(undefined)).toBeNull();
		expect(parseArtistIdParam("")).toBeNull();
		expect(parseArtistIdParam("0")).toBeNull();
		expect(parseArtistIdParam("-3")).toBeNull();
		expect(parseArtistIdParam("1.5")).toBeNull();
		expect(parseArtistIdParam("1e3")).toBeNull();
		expect(parseArtistIdParam(" 5 ")).toBeNull();
		expect(parseArtistIdParam("0x10")).toBeNull();
		expect(parseArtistIdParam("9007199254740993")).toBeNull();
	});
});

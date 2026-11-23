import { describe, expect, it } from "vitest";
import type { ImportProbe } from "../api/importSeries";
import { importScope } from "./scope";

function probe(seasons?: number[]): ImportProbe {
	return {
		kind: "series",
		title: "Show",
		scope: "series",
		seasons,
		episodes: [],
	};
}

describe("importScope", () => {
	it("один сезон — просим сезон", () => {
		expect(importScope(probe([1]))).toBe("season");
		expect(importScope(probe())).toBe("season");
	});

	it("несколько сезонов — просим сериал", () => {
		expect(importScope(probe([1, 2]))).toBe("series");
	});
});

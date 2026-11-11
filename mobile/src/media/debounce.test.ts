import { afterEach, describe, expect, it, vi } from "vitest";
import { createDebouncedValue, SEARCH_DEBOUNCE_MS } from "./debounce";

afterEach(() => {
	vi.useRealTimers();
});

describe("createDebouncedValue", () => {
	it("применяет только последнее значение после паузы 300 мс", () => {
		vi.useFakeTimers();
		const applied: string[] = [];
		const debounced = createDebouncedValue(SEARCH_DEBOUNCE_MS);

		debounced.schedule("d", (value) => applied.push(value));
		debounced.schedule("du", (value) => applied.push(value));
		debounced.schedule("dune", (value) => applied.push(value));

		expect(applied).toEqual([]);
		vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS - 1);
		expect(applied).toEqual([]);
		vi.advanceTimersByTime(1);
		expect(applied).toEqual(["dune"]);
	});

	it("cancel отменяет отложенное применение", () => {
		vi.useFakeTimers();
		const applied: string[] = [];
		const debounced = createDebouncedValue(SEARCH_DEBOUNCE_MS);

		debounced.schedule("dune", (value) => applied.push(value));
		debounced.cancel();
		vi.advanceTimersByTime(SEARCH_DEBOUNCE_MS);

		expect(applied).toEqual([]);
	});
});

import { describe, expect, it, vi } from "vitest";
import { emitLocalReset, subscribeLocalReset } from "./reset";

describe("событие локального сброса", () => {
	it("вызывает подписчиков и уважает отписку", () => {
		const listener = vi.fn();
		const unsubscribe = subscribeLocalReset(listener);

		emitLocalReset();
		expect(listener).toHaveBeenCalledTimes(1);

		unsubscribe();
		emitLocalReset();
		expect(listener).toHaveBeenCalledTimes(1);
	});

	it("вызывает всех подписчиков", () => {
		const first = vi.fn();
		const second = vi.fn();
		const unsubscribeFirst = subscribeLocalReset(first);
		const unsubscribeSecond = subscribeLocalReset(second);

		emitLocalReset();

		expect(first).toHaveBeenCalledTimes(1);
		expect(second).toHaveBeenCalledTimes(1);
		unsubscribeFirst();
		unsubscribeSecond();
	});
});

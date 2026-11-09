import { describe, expect, it } from "vitest";
import { resolveMediaGridState } from "./mediaGridState";

describe("MediaGrid state", () => {
	it("показывает loading, пока нет первой страницы", () => {
		expect(
			resolveMediaGridState({ isPending: true, isError: false, itemCount: 0 }),
		).toBe("loading");
	});

	it("не маскирует ошибку пустым состоянием", () => {
		expect(
			resolveMediaGridState({ isPending: false, isError: true, itemCount: 0 }),
		).toBe("error");
	});

	it("пустой успешный ответ — empty", () => {
		expect(
			resolveMediaGridState({ isPending: false, isError: false, itemCount: 0 }),
		).toBe("empty");
	});

	it("ошибка при непустом списке оставляет карточки и retry в футере", () => {
		expect(
			resolveMediaGridState({ isPending: false, isError: true, itemCount: 5 }),
		).toBe("content");
	});
});

import { fireEvent, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useTVBackNavigation } from "./tvBack";

const backSpy = vi.hoisted(() => vi.fn());

vi.mock("@tanstack/react-router", () => ({
	useRouter: () => ({ history: { back: backSpy } }),
}));

afterEach(() => {
	backSpy.mockClear();
	document.body.innerHTML = "";
});

// biome-ignore lint/security/noSecrets: имя тестируемого хука, не секрет.
describe("useTVBackNavigation", () => {
	it("в ТВ-режиме код пульта уходит в router.history.back()", () => {
		renderHook(() => useTVBackNavigation(true));

		fireEvent.keyDown(document.body, { key: "Unidentified", keyCode: 461 });
		expect(backSpy).toHaveBeenCalledTimes(1);
	});

	it("вне ТВ-режима слушатель не висит", () => {
		renderHook(() => useTVBackNavigation(false));

		fireEvent.keyDown(document.body, { key: "Escape", keyCode: 27 });
		expect(backSpy).not.toHaveBeenCalled();
	});

	it("ввод в инпуте не уходит назад", () => {
		renderHook(() => useTVBackNavigation(true));
		const field = document.createElement("input");
		document.body.appendChild(field);

		fireEvent.keyDown(field, { key: "Backspace", keyCode: 8 });
		expect(backSpy).not.toHaveBeenCalled();
	});
});

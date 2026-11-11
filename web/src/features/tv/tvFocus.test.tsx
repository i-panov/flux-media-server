import { destroy, init } from "@noriginmedia/norigin-spatial-navigation";
import { render } from "@testing-library/react";
import { act } from "react";
import {
	afterAll,
	afterEach,
	beforeAll,
	beforeEach,
	describe,
	expect,
	it,
	vi,
} from "vitest";
import { TVModalAutoFocus, useTVFocusable } from "./tvFocus";

const spatial = vi.hoisted(() => ({
	setFocus: vi.fn(),
	getCurrentFocusKey: vi.fn(),
}));

vi.mock("@noriginmedia/norigin-spatial-navigation", async (importOriginal) => {
	const mod =
		await importOriginal<
			typeof import("@noriginmedia/norigin-spatial-navigation")
		>();
	return {
		...mod,
		setFocus: spatial.setFocus,
		getCurrentFocusKey: spatial.getCurrentFocusKey,
	};
});

const routerSearch = vi.hoisted(() => ({ value: "?tv=1" }));

vi.mock("@tanstack/react-router", () => ({
	useRouterState: (options: {
		select: (state: { location: { searchStr: string } }) => string;
	}): string => options.select({ location: { searchStr: routerSearch.value } }),
}));

beforeAll(() => {
	init({ shouldFocusDOMNode: true });
});

afterAll(() => {
	destroy();
});

beforeEach(() => {
	vi.useFakeTimers();
});

afterEach(() => {
	vi.useRealTimers();
	spatial.setFocus.mockClear();
	spatial.getCurrentFocusKey.mockReset();
	document.body.innerHTML = "";
	routerSearch.value = "?tv=1";
	window.localStorage.clear();
});

function advanceModalFocus(): void {
	act(() => {
		vi.advanceTimersByTime(100);
	});
}

function LateNode({ show }: { show: boolean }) {
	const { targetRef } = useTVFocusable<HTMLButtonElement>("late-node");
	return show ? <button ref={targetRef} type="button" /> : null;
}

describe("useTVFocusable", () => {
	it("ставит data-tv-focus-key узлу, который смонтировался позже", () => {
		// Библиотека предупреждает о регистрации без node — это и есть
		// проверяемый поздний маунт.
		const warn = vi.spyOn(console, "warn").mockImplementation(() => undefined);
		try {
			const { rerender } = render(<LateNode show={false} />);
			rerender(<LateNode show />);
			expect(
				document.querySelector('[data-tv-focus-key="late-node"]'),
			).not.toBeNull();
		} finally {
			warn.mockRestore();
		}
	});
});

describe("TVModalAutoFocus", () => {
	it("ставит spatial-фокус на кнопку модалки без инпута", () => {
		spatial.getCurrentFocusKey.mockReturnValue("");
		render(<TVModalAutoFocus focusKey="delete-media-cancel" />);

		expect(spatial.setFocus).not.toHaveBeenCalled();
		advanceModalFocus();
		expect(spatial.setFocus).toHaveBeenCalledWith("delete-media-cancel");
	});

	it("с data-autofocus-инпутом spatial-фокус не трогает", () => {
		spatial.getCurrentFocusKey.mockReturnValue("card-3");
		render(
			<div role="dialog">
				<input data-autofocus />
				<TVModalAutoFocus focusKey="create-collection-cancel" />
			</div>,
		);

		advanceModalFocus();
		expect(spatial.setFocus).not.toHaveBeenCalled();
	});

	it("при закрытии возвращает фокус на сохранённый ключ", () => {
		spatial.getCurrentFocusKey.mockReturnValue("card-5");
		const { unmount } = render(
			<TVModalAutoFocus focusKey="delete-media-cancel" />,
		);
		advanceModalFocus();

		unmount();

		expect(spatial.setFocus).toHaveBeenLastCalledWith("card-5");
	});

	it("без сохранённого ключа при закрытии ничего не возвращает", () => {
		spatial.getCurrentFocusKey.mockReturnValue("");
		const { unmount } = render(
			<TVModalAutoFocus focusKey="delete-media-cancel" />,
		);
		advanceModalFocus();
		spatial.setFocus.mockClear();

		unmount();

		expect(spatial.setFocus).not.toHaveBeenCalled();
	});

	it("вне ТВ-режима ничего не делает", () => {
		routerSearch.value = "";
		spatial.getCurrentFocusKey.mockReturnValue("card-1");
		const { unmount } = render(
			<TVModalAutoFocus focusKey="delete-media-cancel" />,
		);

		advanceModalFocus();
		unmount();

		expect(spatial.setFocus).not.toHaveBeenCalled();
		expect(spatial.getCurrentFocusKey).not.toHaveBeenCalled();
	});
});

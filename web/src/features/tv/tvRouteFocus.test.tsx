import {
	getCurrentFocusKey,
	setFocus,
} from "@noriginmedia/norigin-spatial-navigation";
import { renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { findTVFocusTarget, useTVRouteFocus } from "./tvRouteFocus";

const routerState = vi.hoisted(() => ({ pathname: "/video" }));

vi.mock("@tanstack/react-router", () => ({
	useRouterState: (options: {
		select: (state: { location: { pathname: string } }) => string;
	}): string =>
		options.select({ location: { pathname: routerState.pathname } }),
}));

const setFocusMock = vi.mocked(setFocus);
const getCurrentFocusKeyMock = vi.mocked(getCurrentFocusKey);
let currentFocusKey = "";

beforeEach(() => {
	currentFocusKey = "";
	setFocusMock.mockReset();
	setFocusMock.mockImplementation((key: string) => {
		currentFocusKey = key;
		return Promise.resolve();
	});
	getCurrentFocusKeyMock.mockImplementation(() => currentFocusKey);
	routerState.pathname = "/video";
	document.body.innerHTML =
		'<main><div data-tv-page-root="true" data-tv-focus-key="video-page"></div></main>';
});

afterEach(() => {
	document.body.innerHTML = "";
});

// biome-ignore lint/security/noSecrets: имя describe, не секрет.
describe("findTVFocusTarget", () => {
	it("предпочитает контент корню страницы", () => {
		document.body.innerHTML =
			'<main><div data-tv-page-root="true" data-tv-focus-key="page"></div><div data-tv-focus-key="card-1"></div></main>';
		const target = findTVFocusTarget(document);
		expect(target?.getAttribute("data-tv-focus-key")).toBe("card-1");
	});

	it("без контента возвращает корень страницы", () => {
		const target = findTVFocusTarget(document);
		expect(target?.getAttribute("data-tv-focus-key")).toBe("video-page");
	});

	it("без целей возвращает main", () => {
		document.body.innerHTML = "<main></main>";
		expect(findTVFocusTarget(document)?.tagName).toBe("MAIN");
	});
});

describe("useTVRouteFocus", () => {
	it("ставит фокус на корень, затем переводит на появившийся контент", async () => {
		renderHook(() => useTVRouteFocus(true));

		await waitFor(() => {
			expect(setFocusMock).toHaveBeenCalledWith("video-page");
		});

		const card = document.createElement("div");
		card.setAttribute("data-tv-focus-key", "video-card-1");
		document.querySelector("main")?.appendChild(card);

		await waitFor(() => {
			expect(setFocusMock).toHaveBeenLastCalledWith("video-card-1");
		});
	});

	it("не перехватывает фокус, если пользователь уже сдвинул его сам", async () => {
		renderHook(() => useTVRouteFocus(true));
		await waitFor(() => {
			expect(setFocusMock).toHaveBeenCalledWith("video-page");
		});

		const userCard = document.createElement("div");
		userCard.setAttribute("data-tv-focus-key", "user-card");
		document.querySelector("main")?.appendChild(userCard);
		currentFocusKey = "user-card";
		await waitFor(() => {
			expect(getCurrentFocusKeyMock).toHaveReturnedWith("user-card");
		});

		const lateCard = document.createElement("div");
		lateCard.setAttribute("data-tv-focus-key", "late-card");
		document.querySelector("main")?.appendChild(lateCard);

		await new Promise((resolve) => setTimeout(resolve, 120));
		expect(setFocusMock).not.toHaveBeenCalledWith("late-card");
	});

	it("не перехватывает фокус, если пользователь сам ушёл в навбар", async () => {
		renderHook(() => useTVRouteFocus(true));
		await waitFor(() => {
			expect(setFocusMock).toHaveBeenCalledWith("video-page");
		});

		// Пользователь ушёл в шапку/навбар — поздние данные не должны
		// возвращать фокус в main.
		const nav = document.createElement("nav");
		const navLink = document.createElement("a");
		navLink.setAttribute("data-tv-focus-key", "nav-home");
		nav.appendChild(navLink);
		document.body.prepend(nav);
		currentFocusKey = "nav-home";
		const lateCard = document.createElement("div");
		lateCard.setAttribute("data-tv-focus-key", "late-card");
		document.querySelector("main")?.appendChild(lateCard);

		await new Promise((resolve) => setTimeout(resolve, 120));
		expect(setFocusMock).not.toHaveBeenCalledWith("late-card");
	});

	it("не сдёргивает фокус с навбара, если он там остался", async () => {
		const nav = document.createElement("nav");
		const navLink = document.createElement("a");
		navLink.setAttribute("data-tv-focus-key", "nav-home");
		nav.appendChild(navLink);
		document.body.prepend(nav);
		currentFocusKey = "nav-home";
		const card = document.createElement("div");
		card.setAttribute("data-tv-focus-key", "late-card");
		document.querySelector("main")?.appendChild(card);

		renderHook(() => useTVRouteFocus(true));

		await new Promise((resolve) => setTimeout(resolve, 120));
		expect(setFocusMock).not.toHaveBeenCalledWith("late-card");
		expect(setFocusMock).not.toHaveBeenCalledWith("video-page");
	});

	it("в обычном режиме фокус не трогает", async () => {
		renderHook(() => useTVRouteFocus(false));
		await new Promise((resolve) => setTimeout(resolve, 80));
		expect(setFocusMock).not.toHaveBeenCalled();
	});
});

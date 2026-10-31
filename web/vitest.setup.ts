import "@testing-library/jest-dom/vitest";
import { beforeAll, vi } from "vitest";
import i18n from "./src/i18n";

beforeAll(async () => {
	await i18n.changeLanguage("ru");
});

Object.defineProperty(window, "matchMedia", {
	writable: true,
	value: vi.fn().mockImplementation((query: string) => ({
		matches: false,
		media: query,
		onchange: null,
		addListener: vi.fn(),
		removeListener: vi.fn(),
		addEventListener: vi.fn(),
		removeEventListener: vi.fn(),
		dispatchEvent: vi.fn(),
	})),
});

class ResizeObserverMock {
	observe() {}

	unobserve() {}

	disconnect() {}
}

vi.stubGlobal("ResizeObserver", ResizeObserverMock);
window.HTMLElement.prototype.scrollIntoView = vi.fn();

// Spatial-навигация падает в jsdom: регистрация нод запускает асинхронный
// замер layout, которого в jsdom нет (`measureLayout` of undefined).
// В реальных браузерах всё работает, поэтому мокаем только тестовое
// окружение. Файловые моки (как в tvFocus.test.tsx) имеют приоритет
// над этим глобальным. Возвращаемые формы повторяют используемые места:
// `useFocusable` → `{ ref, focused }`, `FocusContext.Provider` — passthrough.
vi.mock("@noriginmedia/norigin-spatial-navigation", () => ({
	destroy: vi.fn(),
	FocusContext: {
		Provider: (props: { children?: unknown }) => props.children,
	},
	getCurrentFocusKey: vi.fn(() => ""),
	init: vi.fn(),
	setFocus: vi.fn(),
	useFocusable: vi.fn(() => ({
		focused: false,
		ref: { current: null },
	})),
}));

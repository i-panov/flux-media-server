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

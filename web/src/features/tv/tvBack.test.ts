import { afterEach, describe, expect, it, vi } from "vitest";
import { handleTVBackKey, isBackKey } from "./tvBack";

afterEach(() => {
	document.body.innerHTML = "";
});

interface StubbedKeyEvent {
	event: KeyboardEvent;
	preventDefault: ReturnType<typeof vi.fn>;
}

function stubEvent(init: {
	key: string;
	keyCode: number;
	target: EventTarget | null;
}): StubbedKeyEvent {
	const preventDefault = vi.fn();
	const event = {
		key: init.key,
		keyCode: init.keyCode,
		target: init.target,
		preventDefault,
	} as unknown as KeyboardEvent;
	return { event, preventDefault };
}

describe("isBackKey", () => {
	it.each([461, 10009, 8, 27])("код пульта %i — это Назад", (keyCode) => {
		expect(isBackKey({ key: "Unidentified", keyCode })).toBe(true);
	});

	it.each(["Backspace", "Escape", "GoBack", "BrowserBack"])(
		"клавиша %s — это Назад",
		(key) => {
			expect(isBackKey({ key, keyCode: 0 })).toBe(true);
		},
	);

	it.each([
		{ key: "ArrowLeft", keyCode: 37 },
		{ key: "Enter", keyCode: 13 },
		{ key: "MediaPlayPause", keyCode: 179 },
		{ key: "a", keyCode: 65 },
	])("клавиша $key — не Назад", (event) => {
		expect(isBackKey(event)).toBe(false);
	});
});

describe("handleTVBackKey", () => {
	it("Назад вне ввода вызывает goBack", () => {
		const goBack = vi.fn();
		const { event, preventDefault } = stubEvent({
			key: "Backspace",
			keyCode: 8,
			target: document.body,
		});

		expect(handleTVBackKey(event, goBack)).toBe(true);
		expect(goBack).toHaveBeenCalledTimes(1);
		expect(preventDefault).toHaveBeenCalledTimes(1);
	});

	it.each(["input", "textarea", "select"])(
		"печатание в %s не перехватывается",
		(tag) => {
			const field = document.createElement(tag);
			document.body.appendChild(field);
			const goBack = vi.fn();
			const { event, preventDefault } = stubEvent({
				key: "Backspace",
				keyCode: 8,
				target: field,
			});

			expect(handleTVBackKey(event, goBack)).toBe(false);
			expect(goBack).not.toHaveBeenCalled();
			expect(preventDefault).not.toHaveBeenCalled();
		},
	);

	it("печатание в contentEditable не перехватывается", () => {
		const field = document.createElement("div");
		// jsdom не считает isContentEditable: ставим свойство напрямую —
		// в браузере оно true у хоста и потомков contenteditable.
		Object.defineProperty(field, "isContentEditable", {
			value: true,
			configurable: true,
		});
		document.body.appendChild(field);
		const goBack = vi.fn();
		const { event } = stubEvent({
			key: "Escape",
			keyCode: 27,
			target: field,
		});

		expect(handleTVBackKey(event, goBack)).toBe(false);
		expect(goBack).not.toHaveBeenCalled();
	});

	it("открытая модалка обрабатывает Escape сама", () => {
		const modal = document.createElement("div");
		modal.setAttribute("role", "dialog");
		document.body.appendChild(modal);
		const goBack = vi.fn();
		const { event, preventDefault } = stubEvent({
			key: "Escape",
			keyCode: 27,
			target: document.body,
		});

		expect(handleTVBackKey(event, goBack)).toBe(false);
		expect(goBack).not.toHaveBeenCalled();
		expect(preventDefault).not.toHaveBeenCalled();
	});

	it("закрытая модалка (пустой .mantine-Modal-root) Назад не блокирует", () => {
		// Mantine держит пустой рут закрытой модалки в DOM для транзишена:
		// контента и role нет, Назад должен уходить в историю.
		const root = document.createElement("div");
		root.className = "mantine-Modal-root";
		document.body.appendChild(root);
		const goBack = vi.fn();
		const { event, preventDefault } = stubEvent({
			key: "Escape",
			keyCode: 27,
			target: document.body,
		});

		expect(handleTVBackKey(event, goBack)).toBe(true);
		expect(goBack).toHaveBeenCalledTimes(1);
		expect(preventDefault).toHaveBeenCalledTimes(1);
	});

	it("открытое меню закрывается пультовым Назад, история не трогается", () => {
		// Menu.Dropdown рендерит role="menu" в портале — как в CollectionHeader.
		const menu = document.createElement("div");
		menu.setAttribute("role", "menu");
		menu.className = "mantine-Popover-dropdown";
		document.body.appendChild(menu);
		const escapeSpy = vi.fn();
		window.addEventListener("keydown", escapeSpy);
		const goBack = vi.fn();
		const { event, preventDefault } = stubEvent({
			key: "GoBack",
			keyCode: 461,
			target: document.body,
		});

		expect(handleTVBackKey(event, goBack)).toBe(true);
		expect(goBack).not.toHaveBeenCalled();
		expect(preventDefault).toHaveBeenCalledTimes(1);
		expect(escapeSpy).toHaveBeenCalledTimes(1);
		const synthesized = escapeSpy.mock.calls[0]?.[0] as KeyboardEvent;
		expect(synthesized.key).toBe("Escape");
		window.removeEventListener("keydown", escapeSpy);
	});

	it("открытая модалка закрывается кодом Tizen (10009)", () => {
		const modal = document.createElement("div");
		modal.setAttribute("role", "dialog");
		document.body.appendChild(modal);
		const escapeSpy = vi.fn();
		window.addEventListener("keydown", escapeSpy);
		const goBack = vi.fn();
		const { event, preventDefault } = stubEvent({
			key: "Unidentified",
			keyCode: 10009,
			target: document.body,
		});

		expect(handleTVBackKey(event, goBack)).toBe(true);
		expect(goBack).not.toHaveBeenCalled();
		expect(preventDefault).toHaveBeenCalledTimes(1);
		expect(escapeSpy).toHaveBeenCalledTimes(1);
		window.removeEventListener("keydown", escapeSpy);
	});

	it("пультовый Назад в поле Select закрывает слой", () => {
		const listbox = document.createElement("div");
		listbox.setAttribute("role", "listbox");
		document.body.appendChild(listbox);
		const field = document.createElement("input");
		document.body.appendChild(field);
		const escapeSpy = vi.fn();
		window.addEventListener("keydown", escapeSpy);
		const goBack = vi.fn();
		const { event } = stubEvent({
			key: "GoBack",
			keyCode: 461,
			target: field,
		});

		expect(handleTVBackKey(event, goBack)).toBe(true);
		expect(goBack).not.toHaveBeenCalled();
		expect(escapeSpy).toHaveBeenCalledTimes(1);
		window.removeEventListener("keydown", escapeSpy);
	});

	it("Backspace в поле Select остаётся правкой текста", () => {
		const listbox = document.createElement("div");
		listbox.setAttribute("role", "listbox");
		document.body.appendChild(listbox);
		const field = document.createElement("input");
		document.body.appendChild(field);
		const goBack = vi.fn();
		const { event, preventDefault } = stubEvent({
			key: "Backspace",
			keyCode: 8,
			target: field,
		});

		expect(handleTVBackKey(event, goBack)).toBe(false);
		expect(goBack).not.toHaveBeenCalled();
		expect(preventDefault).not.toHaveBeenCalled();
	});

	it("открытый Select (role=listbox) обрабатывает Назад сам", () => {
		const listbox = document.createElement("div");
		listbox.setAttribute("role", "listbox");
		document.body.appendChild(listbox);
		const goBack = vi.fn();
		const { event } = stubEvent({
			key: "Escape",
			keyCode: 27,
			target: document.body,
		});

		expect(handleTVBackKey(event, goBack)).toBe(false);
		expect(goBack).not.toHaveBeenCalled();
	});

	it("не-Назад игнорируется", () => {
		const goBack = vi.fn();
		const { event } = stubEvent({
			key: "Enter",
			keyCode: 13,
			target: document.body,
		});

		expect(handleTVBackKey(event, goBack)).toBe(false);
		expect(goBack).not.toHaveBeenCalled();
	});
});

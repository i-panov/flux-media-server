import { afterEach, describe, expect, it } from "vitest";
import { clickFirstLink, clickNode } from "../tv/tvFocus";
import {
	resolveTVRemoteAction,
	TV_SEEK_STEP,
	TV_VOLUME_STEP,
} from "./tvPlayerRemote";

function keyEvent(init: {
	key: string;
	keyCode?: number;
	target?: EventTarget | null;
}): Pick<KeyboardEvent, "key" | "keyCode" | "target"> {
	return {
		key: init.key,
		keyCode: init.keyCode ?? 0,
		target: init.target ?? document.body,
	};
}

afterEach(() => {
	document.body.innerHTML = "";
});

describe("resolveTVRemoteAction", () => {
	it("стрелки — seek и громкость", () => {
		expect(resolveTVRemoteAction(keyEvent({ key: "ArrowLeft" }))).toBe(
			"seek-back",
		);
		expect(resolveTVRemoteAction(keyEvent({ key: "ArrowRight" }))).toBe(
			"seek-forward",
		);
		expect(resolveTVRemoteAction(keyEvent({ key: "ArrowUp" }))).toBe(
			"volume-up",
		);
		expect(resolveTVRemoteAction(keyEvent({ key: "ArrowDown" }))).toBe(
			"volume-down",
		);
	});

	it("шаги пульта — 10 секунд и 0.05 громкости", () => {
		expect(TV_SEEK_STEP).toBe(10);
		expect(TV_VOLUME_STEP).toBe(0.05);
	});

	it("Enter и Back не перехватываются", () => {
		expect(resolveTVRemoteAction(keyEvent({ key: "Enter" }))).toBeNull();
		expect(
			resolveTVRemoteAction(keyEvent({ key: "Backspace", keyCode: 8 })),
		).toBeNull();
		expect(
			resolveTVRemoteAction(keyEvent({ key: "Escape", keyCode: 27 })),
		).toBeNull();
		expect(resolveTVRemoteAction(keyEvent({ key: "a" }))).toBeNull();
	});

	it("media-клавиши — транспорт", () => {
		expect(resolveTVRemoteAction(keyEvent({ key: "MediaPlayPause" }))).toBe(
			"toggle",
		);
		expect(resolveTVRemoteAction(keyEvent({ key: "MediaTrackNext" }))).toBe(
			"next",
		);
		expect(resolveTVRemoteAction(keyEvent({ key: "MediaTrackPrevious" }))).toBe(
			"prev",
		);
	});

	it("keyCode-дубли media-клавиш для старых приставок", () => {
		expect(
			resolveTVRemoteAction(keyEvent({ key: "Unidentified", keyCode: 179 })),
		).toBe("toggle");
		expect(
			resolveTVRemoteAction(keyEvent({ key: "Unidentified", keyCode: 176 })),
		).toBe("next");
		expect(
			resolveTVRemoteAction(keyEvent({ key: "Unidentified", keyCode: 177 })),
		).toBe("prev");
	});

	it("ввод текста не трогаем", () => {
		const field = document.createElement("input");
		document.body.appendChild(field);
		expect(
			resolveTVRemoteAction(keyEvent({ key: "ArrowLeft", target: field })),
		).toBeNull();
	});

	it("стрелки на табах переключением владеет Mantine", () => {
		const tablist = document.createElement("div");
		tablist.setAttribute("role", "tablist");
		const tab = document.createElement("button");
		tab.setAttribute("role", "tab");
		tablist.appendChild(tab);
		document.body.appendChild(tablist);
		expect(
			resolveTVRemoteAction(keyEvent({ key: "ArrowRight", target: tab })),
		).toBeNull();
	});

	it("стрелки на слайдере не дублируются: слайдер двигается сам", () => {
		const slider = document.createElement("div");
		slider.setAttribute("role", "slider");
		document.body.appendChild(slider);
		expect(
			resolveTVRemoteAction(keyEvent({ key: "ArrowLeft", target: slider })),
		).toBeNull();
		expect(
			resolveTVRemoteAction(keyEvent({ key: "ArrowUp", target: slider })),
		).toBeNull();
	});

	it("открытая модалка гасит стрелки", () => {
		const modal = document.createElement("div");
		modal.setAttribute("role", "dialog");
		document.body.appendChild(modal);
		expect(resolveTVRemoteAction(keyEvent({ key: "ArrowLeft" }))).toBeNull();
	});
});

describe("tv clicks", () => {
	it("clickFirstLink кликает первую ссылку карточки", () => {
		const card = document.createElement("div");
		const link = document.createElement("a");
		link.href = "/video/1";
		let clicked = 0;
		link.addEventListener("click", (event) => {
			event.preventDefault();
			clicked += 1;
		});
		card.appendChild(link);
		clickFirstLink(card);
		expect(clicked).toBe(1);
	});

	it("clickFirstLink без ссылки молчит", () => {
		expect(() => {
			clickFirstLink(document.createElement("div"));
			clickFirstLink(null);
		}).not.toThrow();
	});

	it("clickNode кликает сам узел", () => {
		const button = document.createElement("button");
		let clicked = 0;
		button.addEventListener("click", () => {
			clicked += 1;
		});
		clickNode(button);
		expect(clicked).toBe(1);
	});
});

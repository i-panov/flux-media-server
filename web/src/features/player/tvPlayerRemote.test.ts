import { afterEach, describe, expect, it, vi } from "vitest";
import { clickFirstLink, clickNode } from "../tv/tvFocus";
import {
	canRequestTVFullscreen,
	changeVideoVolume,
	clampTVSeek,
	clampTVVolume,
	isTVFullscreenActive,
	resolveTVRemoteAction,
	resolveTVVideoRemoteAction,
	seekVideoBy,
	TV_SEEK_STEP,
	TV_VOLUME_STEP,
	toggleTVFullscreen,
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

describe("resolveTVVideoRemoteAction", () => {
	it("стрелки — seek и громкость", () => {
		expect(resolveTVVideoRemoteAction(keyEvent({ key: "ArrowLeft" }))).toBe(
			"seek-back",
		);
		expect(resolveTVVideoRemoteAction(keyEvent({ key: "ArrowRight" }))).toBe(
			"seek-forward",
		);
		expect(resolveTVVideoRemoteAction(keyEvent({ key: "ArrowUp" }))).toBe(
			"volume-up",
		);
		expect(resolveTVVideoRemoteAction(keyEvent({ key: "ArrowDown" }))).toBe(
			"volume-down",
		);
	});

	it("Enter/Space на корне — play/pause, на кнопке — без дубля", () => {
		expect(resolveTVVideoRemoteAction(keyEvent({ key: "Enter" }))).toBe(
			"toggle",
		);
		expect(resolveTVVideoRemoteAction(keyEvent({ key: " " }))).toBe("toggle");
		const button = document.createElement("button");
		document.body.appendChild(button);
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "Enter", target: button })),
		).toBeNull();
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: " ", target: button })),
		).toBeNull();
	});

	it("F и M — полный экран и mute", () => {
		expect(resolveTVVideoRemoteAction(keyEvent({ key: "f" }))).toBe(
			"fullscreen",
		);
		expect(resolveTVVideoRemoteAction(keyEvent({ key: "M" }))).toBe(
			"toggle-mute",
		);
	});

	it("media-клавиши: play/pause и seek вместо треков", () => {
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "MediaPlayPause" })),
		).toBe("toggle");
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "MediaTrackNext" })),
		).toBe("seek-forward");
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "MediaTrackPrevious" })),
		).toBe("seek-back");
		expect(
			resolveTVVideoRemoteAction(
				keyEvent({ key: "Unidentified", keyCode: 179 }),
			),
		).toBe("toggle");
	});

	it("play: ←/→ сикают, ↑/↓ отдаются spatial-навигации", () => {
		const play = document.createElement("button");
		play.setAttribute("data-tv-focus-key", "video-osd-play");
		document.body.appendChild(play);
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "ArrowRight", target: play })),
		).toBe("seek-forward");
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "ArrowLeft", target: play })),
		).toBe("seek-back");
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "ArrowUp", target: play })),
		).toBeNull();
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "ArrowDown", target: play })),
		).toBeNull();
	});

	it("остальные OSD-кнопки стрелками не перехватываются", () => {
		const button = document.createElement("button");
		button.setAttribute("data-tv-focus-key", "video-osd-mute");
		document.body.appendChild(button);
		for (const key of ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"]) {
			expect(
				resolveTVVideoRemoteAction(keyEvent({ key, target: button })),
			).toBeNull();
		}
	});

	it("spatial focusKey не даёт дублировать Enter/Space", () => {
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "Enter" }), "video-osd-play"),
		).toBeNull();
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: " " }), "video-osd-mute"),
		).toBeNull();
		expect(
			resolveTVVideoRemoteAction(
				keyEvent({ key: "ArrowRight" }),
				"video-osd-play",
			),
		).toBe("seek-forward");
		expect(
			resolveTVVideoRemoteAction(
				keyEvent({ key: "ArrowUp" }),
				"video-osd-play",
			),
		).toBeNull();
		expect(
			resolveTVVideoRemoteAction(
				keyEvent({ key: "ArrowDown" }),
				"video-osd-mute",
			),
		).toBeNull();
	});

	it("слайдер и ввод живут нативно, модалка гасит пульт", () => {
		const slider = document.createElement("div");
		slider.setAttribute("role", "slider");
		document.body.appendChild(slider);
		expect(
			resolveTVVideoRemoteAction(
				keyEvent({ key: "ArrowLeft", target: slider }),
			),
		).toBeNull();

		const field = document.createElement("input");
		document.body.appendChild(field);
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "ArrowUp", target: field })),
		).toBeNull();

		const modal = document.createElement("div");
		modal.setAttribute("role", "dialog");
		document.body.appendChild(modal);
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "ArrowLeft" })),
		).toBeNull();
		expect(
			resolveTVVideoRemoteAction(keyEvent({ key: "MediaPlayPause" })),
		).toBeNull();
	});
});

describe("видео-экшены и clamp", () => {
	it("seek не уходит за границы", () => {
		expect(clampTVSeek(5, -TV_SEEK_STEP, 100)).toBe(0);
		expect(clampTVSeek(95, TV_SEEK_STEP, 100)).toBe(100);
		expect(clampTVSeek(5, TV_SEEK_STEP, 0)).toBe(15);
		expect(clampTVSeek(Number.NaN, TV_SEEK_STEP, 100)).toBe(10);
	});

	it("громкость клампится в 0..1", () => {
		expect(clampTVVolume(-0.2)).toBe(0);
		expect(clampTVVolume(1.4)).toBe(1);
		expect(clampTVVolume(0.5)).toBe(0.5);
		expect(clampTVVolume(Number.NaN)).toBe(0);
	});

	it("seekVideoBy и changeVideoVolume работают с элементом", () => {
		const video = {
			currentTime: 95,
			duration: 100,
			volume: 0.98,
			muted: true,
		} as HTMLVideoElement;
		seekVideoBy(video, TV_SEEK_STEP);
		expect(video.currentTime).toBe(100);
		changeVideoVolume(video, TV_VOLUME_STEP);
		expect(video.volume).toBe(1);
		expect(video.muted).toBe(false);
	});
});

describe("fullscreen helpers", () => {
	it("стандартный и legacy WebKit API распознаются", () => {
		const standard = document.createElement("div");
		Object.defineProperty(standard, "requestFullscreen", {
			configurable: true,
			value: () => Promise.resolve(),
		});
		expect(canRequestTVFullscreen(standard)).toBe(true);

		const legacy = document.createElement("div");
		Object.defineProperty(legacy, "requestFullscreen", {
			configurable: true,
			value: undefined,
		});
		Object.defineProperty(legacy, "webkitRequestFullscreen", {
			configurable: true,
			value: vi.fn(),
		});
		expect(canRequestTVFullscreen(legacy)).toBe(true);
		expect(canRequestTVFullscreen(null)).toBe(false);
	});

	it("legacy WebKit request вызывается, если стандартного нет", async () => {
		const legacy = document.createElement("div");
		Object.defineProperty(legacy, "requestFullscreen", {
			configurable: true,
			value: undefined,
		});
		const request = vi.fn();
		Object.defineProperty(legacy, "webkitRequestFullscreen", {
			configurable: true,
			value: request,
		});
		await toggleTVFullscreen(legacy);
		expect(request).toHaveBeenCalledTimes(1);
	});

	it("webkitFullscreenElement учитывается как активный fullscreen", () => {
		const target = document.createElement("div");
		Object.defineProperty(document, "webkitFullscreenElement", {
			configurable: true,
			value: target,
		});
		expect(isTVFullscreenActive()).toBe(true);
		Reflect.deleteProperty(document, "webkitFullscreenElement");
		expect(isTVFullscreenActive()).toBe(false);
	});
});

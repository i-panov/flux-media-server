import { describe, expect, it, vi } from "vitest";
import {
	clampSeek,
	formatTime,
	isUnauthorizedError,
	nextPlaybackRate,
	PLAYBACK_SPEEDS,
	progressRatio,
	timelineBounds,
	updatePlaybackRate,
} from "./videoControls";

const ZERO_TIME = "0:00";

describe("formatTime", () => {
	it("форматирует известную длительность как h:mm:ss / m:ss", () => {
		expect(formatTime(0)).toBe(ZERO_TIME);
		expect(formatTime(59)).toBe("0:59");
		expect(formatTime(61)).toBe("1:01");
		expect(formatTime(3600)).toBe("1:00:00");
	});

	it("отдаёт нулевой отсчёт для не-конечных и отрицательных значений", () => {
		expect(formatTime(Number.NaN)).toBe(ZERO_TIME);
		expect(formatTime(Number.POSITIVE_INFINITY)).toBe(ZERO_TIME);
		expect(formatTime(-5)).toBe(ZERO_TIME);
	});
});

describe("clampSeek", () => {
	it("сдвигает позицию внутри известной длительности", () => {
		expect(clampSeek(10, 10, 100)).toBe(20);
		expect(clampSeek(50, -10, 100)).toBe(40);
	});

	it("не уходит ниже нуля и выше длительности", () => {
		expect(clampSeek(5, -10, 100)).toBe(0);
		expect(clampSeek(95, 10, 100)).toBe(100);
		expect(clampSeek(0, 10, 100)).toBe(10);
	});

	it("при неизвестной длительности ограничивает только снизу", () => {
		expect(clampSeek(10, 10, 0)).toBe(20);
		expect(clampSeek(10, 10, Number.NaN)).toBe(20);
		expect(clampSeek(10, -20, 0)).toBe(0);
	});

	it("возвращает 0 при NaN в позиции или шаге", () => {
		expect(clampSeek(Number.NaN, 10, 100)).toBe(0);
		expect(clampSeek(10, Number.NaN, 100)).toBe(0);
	});
});

describe("PLAYBACK_SPEEDS", () => {
	it("содержит скорости от 0.5 до 2", () => {
		expect(PLAYBACK_SPEEDS).toEqual([0.5, 0.75, 1, 1.25, 1.5, 2]);
	});
});

describe("nextPlaybackRate", () => {
	it("идёт по циклу и заворачивается с последней скорости", () => {
		expect(nextPlaybackRate(0.5)).toBe(0.75);
		expect(nextPlaybackRate(1)).toBe(1.25);
		expect(nextPlaybackRate(1.5)).toBe(2);
		expect(nextPlaybackRate(2)).toBe(0.5);
	});

	it("неизвестную скорость заменяет обычной 1×", () => {
		expect(nextPlaybackRate(3)).toBe(1);
		expect(nextPlaybackRate(Number.NaN)).toBe(1);
	});
});

describe("updatePlaybackRate", () => {
	function fakePlayer(playbackRate: number) {
		return { playbackRate, pause: vi.fn() };
	}

	it("ставит новую скорость и не трогает играющий плеер", () => {
		const player = fakePlayer(1);
		updatePlaybackRate(player, 1.5, true);
		expect(player.playbackRate).toBe(1.5);
		expect(player.pause).not.toHaveBeenCalled();
	});

	it("возвращает паузу, если до смены скорости видео стояло", () => {
		const player = fakePlayer(1);
		updatePlaybackRate(player, 1.25, false);
		expect(player.playbackRate).toBe(1.25);
		expect(player.pause).toHaveBeenCalledOnce();
	});
});

describe("timelineBounds", () => {
	it("округляет длительность и позицию", () => {
		expect(timelineBounds(12.6, 100.4)).toEqual({ max: 100, now: 13 });
	});

	it("клампет now в 0..max", () => {
		expect(timelineBounds(-5, 60)).toEqual({ max: 60, now: 0 });
		expect(timelineBounds(90, 60)).toEqual({ max: 60, now: 60 });
	});

	it("без известной длительности отдаёт нулевые границы", () => {
		expect(timelineBounds(10, 0)).toEqual({ max: 0, now: 0 });
		expect(timelineBounds(Number.NaN, Number.NaN)).toEqual({
			max: 0,
			now: 0,
		});
	});
});

describe("progressRatio", () => {
	it("считает долю просмотра и зажимает её в 0..1", () => {
		expect(progressRatio(30, 60)).toBe(0.5);
		expect(progressRatio(0, 60)).toBe(0);
		expect(progressRatio(60, 60)).toBe(1);
		expect(progressRatio(90, 60)).toBe(1);
	});

	it("возвращает 0 при неизвестной длительности и мусорной позиции", () => {
		expect(progressRatio(10, 0)).toBe(0);
		expect(progressRatio(10, Number.NaN)).toBe(0);
		expect(progressRatio(Number.NaN, 60)).toBe(0);
	});
});

describe("isUnauthorizedError", () => {
	it("распознаёт 401 и unauthorized в тексте ошибки", () => {
		expect(isUnauthorizedError("HTTP 401")).toBe(true);
		expect(isUnauthorizedError("Unauthorized")).toBe(true);
		expect(isUnauthorizedError("401 Unauthorized")).toBe(true);
		expect(isUnauthorizedError("response status 401")).toBe(true);
	});

	it("не путает 401 с другими кодами и словами", () => {
		expect(isUnauthorizedError("4010")).toBe(false);
		expect(isUnauthorizedError("forbidden")).toBe(false);
		expect(isUnauthorizedError("")).toBe(false);
	});
});

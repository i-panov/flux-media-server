import { afterEach, describe, expect, it } from "vitest";
import {
	hrefWithoutTVSearchParam,
	parseTVSearchParam,
	readStoredTVMode,
	TV_MODE_STORAGE_KEY,
	writeStoredTVMode,
} from "./tvMode";

afterEach(() => {
	window.localStorage.clear();
});

describe("parseTVSearchParam", () => {
	it("?tv=1 включает режим", () => {
		expect(parseTVSearchParam("?tv=1")).toBe(true);
	});

	it("значение без вопроса тоже разбирается", () => {
		expect(parseTVSearchParam("tv=1")).toBe(true);
	});

	it("?tv=0 явно выключает режим", () => {
		expect(parseTVSearchParam("?tv=0")).toBe(false);
	});

	it("без параметра возвращает null", () => {
		expect(parseTVSearchParam("")).toBeNull();
		expect(parseTVSearchParam("?foo=1")).toBeNull();
	});
});

describe("hrefWithoutTVSearchParam", () => {
	it("убирает tv, сохраняя остальные параметры", () => {
		window.history.replaceState(null, "", "/settings?tv=1&tab=theme");
		expect(hrefWithoutTVSearchParam()).toBe("/settings?tab=theme");
	});

	it("без tv возвращает null и адрес не трогает", () => {
		window.history.replaceState(null, "", "/settings?tab=theme");
		expect(hrefWithoutTVSearchParam()).toBeNull();
	});
});

describe("stored tv mode", () => {
	it("по умолчанию выключен", () => {
		expect(readStoredTVMode()).toBe(false);
	});

	it("setTVMode пишет флаг в localStorage", () => {
		writeStoredTVMode(true);
		expect(window.localStorage.getItem(TV_MODE_STORAGE_KEY)).toBe("1");
		expect(readStoredTVMode()).toBe(true);
		writeStoredTVMode(false);
		expect(readStoredTVMode()).toBe(false);
	});
});

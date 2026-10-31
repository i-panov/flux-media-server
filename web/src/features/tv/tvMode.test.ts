import { afterEach, describe, expect, it } from "vitest";
import {
	parseTVSearchParam,
	readInitialTVMode,
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

describe("readInitialTVMode", () => {
	it("URL-параметр побеждает сохранённый флаг", () => {
		writeStoredTVMode(false);
		expect(readInitialTVMode("?tv=1")).toBe(true);
		writeStoredTVMode(true);
		expect(readInitialTVMode("?tv=0")).toBe(false);
	});

	it("без параметра берётся сохранённый флаг", () => {
		writeStoredTVMode(true);
		expect(readInitialTVMode("")).toBe(true);
		expect(readInitialTVMode("?foo=1")).toBe(true);
	});
});

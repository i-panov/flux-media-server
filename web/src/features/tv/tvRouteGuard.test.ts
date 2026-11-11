import { afterEach, describe, expect, it } from "vitest";
import { detectClientProfile } from "./clientProfile";
import { TV_MODE_STORAGE_KEY } from "./tvMode";
import {
	isTVModeAtLocation,
	isTVReadOnlyPath,
	shouldBlockTVRoute,
} from "./tvRouteGuard";

const DESKTOP = detectClientProfile({ userAgent: "Mozilla/5.0 Chrome/130" });
const TV = detectClientProfile({ userAgent: "SmartTV" });

afterEach(() => {
	window.localStorage.clear();
});

// biome-ignore lint/security/noSecrets: имя describe, не секрет.
describe("isTVReadOnlyPath", () => {
	it.each(["/upload", "/upload/", "/trash", "/trash/", "/admin", "/admin/"])(
		"%s — write-маршрут",
		(pathname) => {
			expect(isTVReadOnlyPath(pathname)).toBe(true);
		},
	);

	it.each(["/", "/video", "/video/2", "/settings", "/collections/3"])(
		"%s — не write-маршрут",
		(pathname) => {
			expect(isTVReadOnlyPath(pathname)).toBe(false);
		},
	);
});

describe("isTVModeAtLocation", () => {
	it("?tv=1 включает ТВ независимо от сохранённого выбора", () => {
		window.localStorage.setItem(TV_MODE_STORAGE_KEY, "0");
		expect(isTVModeAtLocation("?tv=1", DESKTOP)).toBe(true);
	});

	it("?tv=0 выключает ТВ независимо от сохранённого выбора", () => {
		window.localStorage.setItem(TV_MODE_STORAGE_KEY, "1");
		expect(isTVModeAtLocation("?tv=0", TV)).toBe(false);
	});

	it("сохранённый выбор старше автоопределения", () => {
		window.localStorage.setItem(TV_MODE_STORAGE_KEY, "1");
		expect(isTVModeAtLocation("", DESKTOP)).toBe(true);
		window.localStorage.setItem(TV_MODE_STORAGE_KEY, "0");
		expect(isTVModeAtLocation("", TV)).toBe(false);
	});

	it("без параметра и выбора решает профиль", () => {
		expect(isTVModeAtLocation("", TV)).toBe(true);
		expect(isTVModeAtLocation("", DESKTOP)).toBe(false);
	});
});

describe("shouldBlockTVRoute", () => {
	// biome-ignore lint/security/noSecrets: имя теста, не секрет.
	it("прямой заход в /upload с ?tv=1 блокируется", () => {
		expect(shouldBlockTVRoute("/upload", "?tv=1", DESKTOP)).toBe(true);
	});

	it("в обычном режиме write-маршруты доступны", () => {
		expect(shouldBlockTVRoute("/upload", "", DESKTOP)).toBe(false);
		expect(shouldBlockTVRoute("/trash", "?tv=0", TV)).toBe(false);
	});

	it("ТВ-профиль блокирует /admin и /trash и без параметра", () => {
		expect(shouldBlockTVRoute("/admin", "", TV)).toBe(true);
		expect(shouldBlockTVRoute("/trash", "", TV)).toBe(true);
	});

	it("read-маршруты не блокируются даже в ТВ", () => {
		expect(shouldBlockTVRoute("/video", "?tv=1", TV)).toBe(false);
	});
});

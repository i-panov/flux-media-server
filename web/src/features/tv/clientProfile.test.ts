import { afterEach, describe, expect, it } from "vitest";
import {
	type ClientProfile,
	type ClientProfileInput,
	detectClientProfile,
	resolveTVMode,
} from "./clientProfile";

const DESKTOP_UA =
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36";

function profileOf(input: Partial<ClientProfileInput>) {
	return detectClientProfile({ userAgent: "", ...input });
}

function tvProfile(): ClientProfile {
	return profileOf({ userAgent: "SmartTV" });
}

afterEach(() => {
	window.localStorage.clear();
});

describe("detectClientProfile", () => {
	it.each([
		"Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36",
		"Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36",
		"Mozilla/5.0 (Linux; Android 11; BRAVIA 4K) AppleWebKit/537.36",
		"Mozilla/5.0 (Linux; Android 9; AFTMM Build/PS7233) AppleWebKit/537.36",
		"Mozilla/5.0 (Linux; Android 11; Chromecast) AppleWebKit/537.36 CrKey/1.56",
	])("ТВ-UA %s даёт режим ТВ", (userAgent) => {
		const profile = detectClientProfile({ userAgent });
		expect(profile.isTV).toBe(true);
		expect(profile.kind).toBe("tv");
		expect(profile.ambiguous).toBe(false);
		expect(profile.signals).toContain("ua");
	});

	// biome-ignore lint/security/noSecrets: имя теста, не секрет.
	it("платформенный API Tizen включает ТВ без UA", () => {
		const profile = profileOf({ tizen: true });
		expect(profile.isTV).toBe(true);
		expect(profile.signals).toContain("tizen");
	});

	it("webOS/VIDAA/HbbTV тоже сильные сигналы", () => {
		expect(profileOf({ webOS: true }).isTV).toBe(true);
		expect(profileOf({ vidaa: true }).isTV).toBe(true);
		expect(profileOf({ hbbtv: true }).isTV).toBe(true);
	});

	it("hover:none без ТВ-признаков — неоднозначный клиент", () => {
		const profile = profileOf({ hoverNone: true, maxTouchPoints: 0 });
		expect(profile.isTV).toBe(false);
		expect(profile.kind).toBe("desktop");
		expect(profile.ambiguous).toBe(true);
	});

	it("обычный десктоп без сигналов не неоднозначен", () => {
		const profile = profileOf({
			userAgent: DESKTOP_UA,
			maxTouchPoints: 0,
			screenWidth: 1920,
			screenHeight: 1080,
			outerWidth: 1920,
			outerHeight: 1080,
		});
		expect(profile.isTV).toBe(false);
		expect(profile.isMobile).toBe(false);
		expect(profile.ambiguous).toBe(false);
	});

	it("телефон с coarse pointer остаётся мобильным, без ТВ-подсказки", () => {
		const profile = profileOf({
			userAgent:
				"Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Mobile",
			pointerCoarse: true,
			maxTouchPoints: 5,
		});
		expect(profile.isTV).toBe(false);
		expect(profile.isMobile).toBe(true);
		expect(profile.ambiguous).toBe(false);
	});

	it("слабые сигналы большого экрана сами ТВ не включают", () => {
		const profile = profileOf({
			userAgent: DESKTOP_UA,
			screenWidth: 3840,
			screenHeight: 2160,
			outerWidth: 3840,
			outerHeight: 2160,
		});
		expect(profile.isTV).toBe(false);
		expect(profile.ambiguous).toBe(false);
	});
});

describe("resolveTVMode", () => {
	const profile = tvProfile();

	it("URL-параметр старше сохранённого выбора и профиля", () => {
		expect(
			resolveTVMode(true, false, detectClientProfile({ userAgent: "" })),
		).toBe(true);
		expect(resolveTVMode(false, true, profile)).toBe(false);
	});

	it("сохранённый явный выбор старше автоопределения", () => {
		expect(resolveTVMode(null, false, profile)).toBe(false);
		expect(
			resolveTVMode(null, true, detectClientProfile({ userAgent: "" })),
		).toBe(true);
	});

	it("без выбора и параметра решает профиль", () => {
		expect(resolveTVMode(null, null, profile)).toBe(true);
		expect(
			resolveTVMode(null, null, detectClientProfile({ userAgent: "" })),
		).toBe(false);
	});
});

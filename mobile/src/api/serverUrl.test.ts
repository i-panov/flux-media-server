import { describe, expect, it } from "vitest";
import { normalizeServerUrl } from "./serverUrl";

const HOST = "https://host";

describe("normalizeServerUrl", () => {
	it("добавляет https и /api к публичному адресу без схемы", () => {
		expect(normalizeServerUrl("flux.ithub24.ru")).toBe(
			"https://flux.ithub24.ru/api",
		);
	});

	it("добавляет http для локального адреса без схемы", () => {
		expect(normalizeServerUrl("192.168.1.10:8080")).toBe(
			"http://192.168.1.10:8080/api",
		);
	});

	it("не дублирует /api и режет хвостовой слэш", () => {
		expect(normalizeServerUrl(`${HOST}/api/`)).toBe(`${HOST}/api`);
		expect(normalizeServerUrl(`${HOST}/api`)).toBe(`${HOST}/api`);
	});

	it("чинит регистр /API", () => {
		expect(normalizeServerUrl(`${HOST}/API`)).toBe(`${HOST}/api`);
	});

	it("добавляет /api к пути, который не заканчивается на api", () => {
		expect(normalizeServerUrl(`${HOST}/base`)).toBe(`${HOST}/base/api`);
	});

	it("отбрасывает query, fragment и userinfo", () => {
		// biome-ignore lint/security/noSecrets: тестовый URL без реального секрета.
		expect(normalizeServerUrl("https://user:pass@host/api?x=1#top")).toBe(
			`${HOST}/api`,
		);
	});

	it("отклоняет не-http схемы и пустой хост", () => {
		expect(normalizeServerUrl("ftp://host")).toBeNull();
		expect(normalizeServerUrl("https://")).toBeNull();
		expect(normalizeServerUrl("")).toBeNull();
	});
});

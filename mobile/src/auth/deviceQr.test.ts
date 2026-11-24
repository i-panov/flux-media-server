// biome-ignore-all lint/security/noSecrets: тестовые шестизначные коды — не секреты.
import { describe, expect, it } from "vitest";
import { parseDeviceCodeFromQr } from "./deviceQr";

describe("parseDeviceCodeFromQr", () => {
	it("достаёт код из verification_uri_complete", () => {
		expect(
			parseDeviceCodeFromQr("https://flux.example/activate#code=123456"),
		).toBe("123456");
	});

	it("понимает query, hash и голый код", () => {
		expect(
			parseDeviceCodeFromQr("https://flux.example/activate?code=654321"),
		).toBe("654321");
		expect(
			parseDeviceCodeFromQr(
				"https://flux.example/activate?code=111111#code=222222",
			),
		).toBe("222222");
		expect(parseDeviceCodeFromQr("123 456")).toBe("123456");
		expect(parseDeviceCodeFromQr("012345")).toBe("012345");
	});

	it("отбрасывает мусор, пути и неполные коды", () => {
		expect(
			parseDeviceCodeFromQr("https://example.com/video/123456"),
		).toBeNull();
		expect(
			parseDeviceCodeFromQr("https://example.com/activate#code=12345"),
		).toBeNull();
		expect(
			parseDeviceCodeFromQr("https://example.com/activate#code=1234567"),
		).toBeNull();
		expect(parseDeviceCodeFromQr("abc123456")).toBeNull();
		expect(parseDeviceCodeFromQr("12345")).toBeNull();
		expect(parseDeviceCodeFromQr("")).toBeNull();
	});
});

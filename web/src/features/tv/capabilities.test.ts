import { describe, expect, it } from "vitest";
import { capabilitiesForProfile, capabilitiesForTVMode } from "./capabilities";
import { detectClientProfile } from "./clientProfile";

describe("capabilitiesForTVMode", () => {
	it("ТВ-режим оставляет только чтение и скачивание", () => {
		const caps = capabilitiesForTVMode(true);
		expect(caps).toMatchObject({
			canUpload: false,
			canEditMetadata: false,
			canChangeCover: false,
			canDelete: false,
			canManageTrash: false,
			canDownload: true,
			canManageCollections: false,
			canUseQrLogin: false,
		});
	});

	it("обычный режим сохраняет desktop-возможности", () => {
		const caps = capabilitiesForTVMode(false);
		expect(caps).toMatchObject({
			canUpload: true,
			canEditMetadata: true,
			canChangeCover: true,
			canDelete: true,
			canManageTrash: true,
			canDownload: true,
			canManageCollections: true,
		});
	});

	it("QR-вход выключен для всех до следующей фазы", () => {
		expect(capabilitiesForTVMode(true).canUseQrLogin).toBe(false);
		expect(capabilitiesForTVMode(false).canUseQrLogin).toBe(false);
	});

	it("профиль ТВ даёт read-only, профиль десктопа — полный набор", () => {
		const tv = capabilitiesForProfile(
			detectClientProfile({ userAgent: "SmartTV" }),
		);
		const desktop = capabilitiesForProfile(
			detectClientProfile({ userAgent: "Mozilla/5.0 Chrome/130" }),
		);
		expect(tv.canUpload).toBe(false);
		expect(desktop.canUpload).toBe(true);
	});
});

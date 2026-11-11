import { describe, expect, it } from "vitest";
import { nextSessionResetState } from "./sessionReset";

describe("переход сессии и сброс локальных данных", () => {
	it("холодный старт без входа не чистит сохранённое", () => {
		expect(nextSessionResetState(false, undefined)).toEqual({
			hadSession: false,
			reset: false,
		});
		expect(nextSessionResetState(false, null)).toEqual({
			hadSession: false,
			reset: false,
		});
	});

	it("после входа запоминает сессию без сброса", () => {
		expect(nextSessionResetState(false, { id: 1 })).toEqual({
			hadSession: true,
			reset: false,
		});
		expect(nextSessionResetState(true, { id: 1 })).toEqual({
			hadSession: true,
			reset: false,
		});
	});

	it("не теряет отметку входа на промежуточном undefined", () => {
		expect(nextSessionResetState(true, undefined)).toEqual({
			hadSession: true,
			reset: false,
		});
	});

	it("logout и смена сервера (user → null) дают reset", () => {
		expect(nextSessionResetState(true, null)).toEqual({
			hadSession: false,
			reset: true,
		});
	});

	it("повторный null не сбрасывает данные второй раз", () => {
		expect(nextSessionResetState(false, null)).toEqual({
			hadSession: false,
			reset: false,
		});
	});
});

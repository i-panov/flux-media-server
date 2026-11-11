import { beforeEach, describe, expect, it, vi } from "vitest";
import {
	LANGUAGE_STORAGE_KEY,
	loadLanguage,
	saveLanguage,
} from "./languageStorage";

const storage = vi.hoisted(() => ({
	getItem: vi.fn(),
	setItem: vi.fn(),
}));

vi.mock("@react-native-async-storage/async-storage", () => ({
	default: storage,
}));

describe("сохранённый язык", () => {
	beforeEach(() => {
		storage.getItem.mockReset();
		storage.setItem.mockReset();
		storage.setItem.mockResolvedValue(undefined);
	});

	it("читает ru/en и отбрасывает неизвестное значение", async () => {
		storage.getItem.mockResolvedValue("ru");
		await expect(loadLanguage()).resolves.toBe("ru");
		expect(storage.getItem).toHaveBeenCalledWith(LANGUAGE_STORAGE_KEY);

		storage.getItem.mockResolvedValue("en");
		await expect(loadLanguage()).resolves.toBe("en");

		storage.getItem.mockResolvedValue("de");
		await expect(loadLanguage()).resolves.toBeNull();
	});

	it("при ошибке хранилища остаётся системный язык", async () => {
		storage.getItem.mockRejectedValue(new Error("storage"));
		await expect(loadLanguage()).resolves.toBeNull();
	});

	it("сохраняет выбор и не падает при ошибке записи", async () => {
		await saveLanguage("ru");
		expect(storage.setItem).toHaveBeenCalledWith(LANGUAGE_STORAGE_KEY, "ru");

		storage.setItem.mockRejectedValue(new Error("storage"));
		await expect(saveLanguage("en")).resolves.toBeUndefined();
	});
});

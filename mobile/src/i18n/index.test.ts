import { afterEach, describe, expect, it } from "vitest";
import { getLanguage, setLanguage, t } from "./index";

describe("mobile i18n", () => {
	afterEach(() => {
		setLanguage("ru");
	});

	it("переключает язык и подставляет значения", () => {
		setLanguage("en");
		expect(getLanguage()).toBe("en");
		expect(t("login.devCode", { code: "1234" })).toBe("Debug code: 1234");
		setLanguage("ru");
		expect(t("login.devCode", { code: "1234" })).toBe("Debug-код: 1234");
	});

	it("неизвестный ключ не ломает рендер", () => {
		expect(t("common.loading")).not.toBe("");
	});

	it("включает строки метаданных и обложки", () => {
		setLanguage("ru");
		expect(t("metadata.edit")).toBe("Редактировать");
		expect(t("cover.change")).toBe("Заменить обложку");
		setLanguage("en");
		expect(t("metadata.edit")).toBe("Edit");
		expect(t("cover.change")).toBe("Change cover");
	});

	it("включает нейтральный заголовок экспорта и имя файла в a11y", () => {
		setLanguage("ru");
		expect(t("downloads.exportDialog")).toBe("Поделиться файлом");
		expect(t("downloads.exportItem", { title: "Фильм" })).toBe(
			"Экспорт: Фильм",
		);
		expect(t("downloads.deleteItem", { title: "Фильм" })).toBe(
			"Удалить: Фильм",
		);
		setLanguage("en");
		expect(t("downloads.exportDialog")).toBe("Share file");
		expect(t("downloads.exportItem", { title: "Movie" })).toBe("Export: Movie");
	});
});

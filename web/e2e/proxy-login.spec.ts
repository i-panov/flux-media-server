import { expect, test } from "@playwright/test";

// Сквозной тест связки «браузер → Vite-прокси → бэкенд» без page.route:
// запросы реально идут через прокси в e2e/fake-backend.mjs. Если прокси
// перепишет Host (changeOrigin), проверка Origin/Host на бэкенде даст 403.
test("вход через реальный прокси: Host совпадает с Origin", async ({
	page,
}) => {
	await page.goto("/");

	await expect(
		page.getByRole("heading", { level: 1, name: "Вход" }),
	).toBeVisible();
	await page.getByLabel("Электронная почта").fill("user@example.com");
	await page.getByRole("button", { name: "Получить код" }).click();

	await expect(
		page.getByText("Код отправлен на user@example.com"),
	).toBeVisible();
	await page.getByLabel("Код из письма").fill("123456");
	await page.getByRole("button", { name: "Войти" }).click();

	await expect(
		page.getByRole("heading", { level: 1, name: "Flux" }),
	).toBeVisible();
	await expect(page.getByText("user@example.com")).toBeVisible();
	// Версия от fake-backend доказывает, что и health шёл через прокси.
	await expect(page.getByText("0.0.0-fake")).toBeVisible();
});

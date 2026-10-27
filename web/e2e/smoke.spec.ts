import { expect, test } from "@playwright/test";

const healthBody = JSON.stringify({ status: "ok", version: "1.0.8" });

test("главная показывает приложение и статус сервера", async ({ page }) => {
	await page.route("**/api/health", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: healthBody,
		}),
	);

	await page.goto("/");

	await expect(
		page.getByRole("heading", { level: 1, name: "Flux" }),
	).toBeVisible();
	await expect(page.getByText("1.0.8")).toBeVisible();
	await expect(page.getByText("Онлайн")).toBeVisible();
});

test("настройки открываются из шапки", async ({ page }) => {
	await page.route("**/api/health", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: healthBody,
		}),
	);

	await page.goto("/");
	await page.getByRole("link", { name: "Настройки" }).click();

	await expect(
		page.getByRole("heading", { level: 1, name: "Настройки" }),
	).toBeVisible();
	await expect(page.getByText("Версия бэкенда")).toBeVisible();
});

test("неизвестный маршрут показывает страницу 404", async ({ page }) => {
	await page.goto("/unknown");

	await expect(
		page.getByRole("heading", { level: 1, name: "404" }),
	).toBeVisible();
	await expect(page.getByText("Страница не найдена")).toBeVisible();

	await page.getByRole("button", { name: "На главную" }).click();
	await expect(
		page.getByRole("heading", { level: 1, name: "Flux" }),
	).toBeVisible();
});

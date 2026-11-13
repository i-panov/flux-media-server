import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const LOGIN_PATTERN = /\/login$/;

async function stubSettings(
	page: Page,
	options: { healthFails?: boolean } = {},
) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 1,
				email: "user@example.com",
				is_admin: true,
			}),
		}),
	);
	await stubEmptyLibraryMeta(page);
	await page.route(
		(url) => url.pathname === "/api/health",
		(route) => {
			if (options.healthFails === true) {
				return route.fulfill({
					status: 500,
					contentType: "application/json",
					body: JSON.stringify({ error: "boom" }),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ status: "ok", version: "9.9.9" }),
			});
		},
	);
	await page.route("**/api/auth/logout-refresh", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ message: "ok" }),
		}),
	);
}

test("настройки: версии веба и бэкенда видны", async ({ page }) => {
	await stubSettings(page);
	await page.goto("/settings");

	await expect(
		page.getByRole("heading", { level: 1, name: "Настройки" }),
	).toBeVisible();
	await expect(page.getByText("Версия веба")).toBeVisible();
	await expect(page.getByText("Версия бэкенда")).toBeVisible();
	await expect(page.getByText("9.9.9")).toBeVisible();
	await expect(
		page.getByRole("main").getByText("user@example.com"),
	).toBeVisible();
});

test("настройки: ошибка сервера показывает повтор", async ({ page }) => {
	await stubSettings(page, { healthFails: true });
	await page.goto("/settings");

	await expect(page.getByText("Сервер недоступен")).toBeVisible();
	// Повтор при лежащем сервере: алерт остаётся, запрос уходит снова.
	await page.getByRole("button", { name: "Повторить" }).click();
	await expect(page.getByText("Сервер недоступен")).toBeVisible();
});

test("настройки: тема и язык переключаются", async ({ page }) => {
	await stubSettings(page);
	await page.goto("/settings");

	await page.getByText("Тёмная", { exact: true }).click();
	await expect(page.locator("html")).toHaveAttribute(
		"data-mantine-color-scheme",
		"dark",
	);

	await page.getByRole("combobox").click();
	await page.getByRole("option", { name: "English" }).click();
	await expect(
		page.getByRole("heading", { level: 1, name: "Settings" }),
	).toBeVisible();
});

test("настройки: выход ведёт на логин", async ({ page }) => {
	await stubSettings(page);
	await page.goto("/settings");

	await page.getByRole("button", { name: "Выйти из аккаунта" }).click();
	await expect(page).toHaveURL(LOGIN_PATTERN);
});

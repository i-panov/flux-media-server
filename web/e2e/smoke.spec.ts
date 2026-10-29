import { expect, type Page, test } from "@playwright/test";

const healthBody = JSON.stringify({ status: "ok", version: "1.0.8" });
const userBody = JSON.stringify({
	id: 1,
	email: "user@example.com",
	is_admin: false,
});
const VIDEO_DETAIL_PATTERN = /\/video\/1$/;
// Имя ссылки блока собирается из названия, остатка и aria-label полосы.
const CONTINUE_LINK_PATTERN = /Осталось 42:05/;

async function stubAuthedSession(page: Page) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: userBody,
		}),
	);
	// Блок «Продолжить просмотр» есть и на главной: без стаба он ходил бы
	// в живой бэкенд и зависел от его содержимого.
	await page.route(
		(url) => url.pathname === "/api/progress",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 20, offset: 0 }),
			}),
	);
}

test("главная показывает приложение и статус сервера", async ({ page }) => {
	await stubAuthedSession(page);
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
	await stubAuthedSession(page);
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
	await stubAuthedSession(page);
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

test("главная: «Продолжить просмотр» открывает фильм с сохранённой позицией", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await page.route("**/api/health", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: healthBody,
		}),
	);
	await page.route(
		(url) => url.pathname === "/api/progress",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [
						{
							id: 1,
							user_id: 1,
							media_id: 1,
							position: 1200,
							duration: 3725,
							completed: false,
							updated_at: "2026-01-01T00:00:00Z",
							media: {
								id: 1,
								title: "Первый фильм",
								year: 2024,
								description: "Описание",
								type: "video",
								duration: 3725,
								width: 1920,
								height: 1080,
								file_size: 100,
								thumbnail_url: "",
								cover_url: "",
								view_count: 1,
								created_at: "2026-01-01T00:00:00Z",
							},
						},
					],
					total: 1,
					limit: 20,
					offset: 0,
				}),
			}),
	);
	await page.route("**/api/media/1", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 1,
				title: "Первый фильм",
				year: 2024,
				description: "Описание",
				type: "video",
				duration: 3725,
				width: 1920,
				height: 1080,
				file_size: 100,
				thumbnail_url: "",
				cover_url: "",
				view_count: 1,
				created_at: "2026-01-01T00:00:00Z",
			}),
		}),
	);
	await page.route("**/api/media/1/subs", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: "[]",
		}),
	);

	await page.goto("/");
	await expect(
		page.getByRole("heading", { level: 1, name: "Flux" }),
	).toBeVisible();
	await expect(
		page.getByRole("heading", { name: "Продолжить просмотр" }),
	).toBeVisible();

	await page.getByRole("link", { name: CONTINUE_LINK_PATTERN }).click();
	await expect(page).toHaveURL(VIDEO_DETAIL_PATTERN);
	await expect(page.locator("video")).toBeVisible();
});

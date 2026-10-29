import type { Page } from "@playwright/test";

// Общие пустые ответы для страниц разделов: без них карточки уходят
// в живой бэкенд за избранным и коллекциями.
export async function stubEmptyLibraryMeta(page: Page): Promise<void> {
	await page.route(
		(url) => url.pathname === "/api/collections",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: "[]",
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/favorites",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 200, offset: 0 }),
			}),
	);
}

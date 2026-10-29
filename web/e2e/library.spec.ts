import { expect, type Page, test } from "@playwright/test";

const COLLECTION_DETAIL_PATTERN = /\/collections\/1$/;
const NESTED_COLLECTION_PATTERN = /\/collections\/2$/;
const TRASH_PATTERN = /\/trash$/;

function videoItem(id: number, title: string) {
	return {
		id,
		title,
		filename: `film-${id}.mkv`,
		year: 2024,
		description: `Описание ${title}`,
		type: "video",
		artists: [],
		album: "",
		genre: "",
		duration: 3725,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: "",
		view_count: 3,
		created_at: "2026-01-01T00:00:00Z",
	};
}

function listBody(items: ReturnType<typeof videoItem>[], total: number) {
	return JSON.stringify({ items, total, limit: 24, offset: 0 });
}

function favoritesBody(media: ReturnType<typeof videoItem>[]) {
	return JSON.stringify({
		items: media.map((item) => ({
			id: item.id,
			user_id: 1,
			media_id: item.id,
			media: item,
			created_at: "2026-01-01T00:00:00Z",
		})),
		total: media.length,
		limit: 200,
		offset: 0,
	});
}

async function stubLibrary(page: Page) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 1,
				email: "user@example.com",
				is_admin: false,
			}),
		}),
	);
	await page.route(
		(url) => url.pathname === "/api/progress",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 20, offset: 0 }),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: listBody(
					[videoItem(1, "Первый фильм"), videoItem(2, "Второй фильм")],
					2,
				),
			}),
	);
}

test("корзина: восстановление и окончательное удаление", async ({ page }) => {
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
	let collections = [
		{
			id: 5,
			user_id: 1,
			name: "Старая коллекция",
			type: "video",
			parent_id: null,
			created_at: "2026-01-01T00:00:00Z",
			updated_at: "2026-01-01T00:00:00Z",
		},
	];
	let media = [videoItem(9, "Удалённый фильм")];
	await page.route(
		(url) => url.pathname === "/api/trash",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ collections, media }),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/trash/collections/5/restore",
		(route) => {
			collections = [];
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ message: "ok" }),
			});
		},
	);
	await page.route(
		(url) => url.pathname === "/api/trash/media/9",
		(route) => {
			media = [];
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ message: "ok" }),
			});
		},
	);

	await page.goto("/settings");
	await page.getByRole("link", { name: "Корзина" }).click();
	await expect(page).toHaveURL(TRASH_PATTERN);
	await expect(page.getByText("Старая коллекция")).toBeVisible();
	await expect(page.getByText("Удалённый фильм")).toBeVisible();

	await page.getByRole("button", { name: "Восстановить" }).first().click();
	await expect(page.getByText("Старая коллекция")).toBeHidden();

	await page.getByRole("button", { name: "Удалить навсегда" }).click();
	await expect(page.getByText("Удалённый фильм")).toBeHidden();
	await expect(page.getByText("Корзина пуста")).toBeVisible();
});

test("корзина: ошибка восстановления показывается", async ({ page }) => {
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
	await page.route(
		(url) => url.pathname === "/api/trash",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					collections: [],
					media: [videoItem(9, "Конфликтный фильм")],
				}),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/trash/media/9/restore",
		(route) =>
			route.fulfill({
				status: 409,
				contentType: "application/json",
				body: JSON.stringify({
					error: "Live media already exists at this path",
				}),
			}),
	);

	await page.goto("/trash");
	await page.getByRole("button", { name: "Восстановить" }).click();
	await expect(page.getByText("Не удалось выполнить действие")).toBeVisible();
	await expect(page.getByText("Конфликтный фильм")).toBeVisible();
});

test("избранное и коллекции: добавить, убрать, создать и открыть", async ({
	page,
}) => {
	await stubLibrary(page);

	let favorites: ReturnType<typeof videoItem>[] = [];
	await page.route(
		(url) => url.pathname === "/api/favorites",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: favoritesBody(favorites),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/favorite",
		(route) => {
			if (route.request().method() === "DELETE") {
				favorites = [];
				return route.fulfill({
					status: 200,
					contentType: "application/json",
					body: JSON.stringify({ message: "Favorite removed" }),
				});
			}
			favorites = [videoItem(1, "Первый фильм")];
			return route.fulfill({
				status: 201,
				contentType: "application/json",
				body: JSON.stringify({ message: "ok" }),
			});
		},
	);

	const collections: Array<{
		id: number;
		user_id: number;
		name: string;
		type: string;
		parent_id: number | null;
		created_at: string;
		updated_at: string;
	}> = [];
	await page.route(
		(url) => url.pathname === "/api/collections",
		(route) => {
			if (route.request().method() === "POST") {
				collections.push({
					id: 1,
					user_id: 1,
					name: "Тестовая",
					type: "video",
					parent_id: null,
					created_at: "2026-01-01T00:00:00Z",
					updated_at: "2026-01-01T00:00:00Z",
				});
				collections.push({
					id: 2,
					user_id: 1,
					name: "Сезон 1",
					type: "video",
					parent_id: 1,
					created_at: "2026-01-01T00:00:00Z",
					updated_at: "2026-01-01T00:00:00Z",
				});
			}
			return route.fulfill({
				status: route.request().method() === "POST" ? 201 : 200,
				contentType: "application/json",
				body: JSON.stringify(collections),
			});
		},
	);
	await page.route(
		(url) => url.pathname === "/api/collections/1/items",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: "[]",
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/collections/2/items",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: "[]",
			}),
	);

	await page.goto("/video");
	await expect(page.getByRole("link", { name: "Первый фильм" })).toBeVisible();

	await page
		.getByRole("button", { name: "Добавить в избранное" })
		.first()
		.click();
	await expect(
		page.getByRole("heading", { level: 2, name: "Избранное" }),
	).toBeVisible();
	await expect(
		page.getByRole("button", { name: "Убрать из избранного" }),
	).toBeVisible();

	await page.getByRole("button", { name: "Убрать из избранного" }).click();
	await expect(
		page.getByRole("heading", { level: 2, name: "Избранное" }),
	).toBeHidden();

	await page.getByRole("button", { name: "Создать коллекцию" }).click();
	const dialog = page.getByRole("dialog");
	await dialog.getByLabel("Название").fill("Тестовая");
	await dialog.getByRole("button", { name: "Создать коллекцию" }).click();

	await expect(page.getByRole("link", { name: "Тестовая" })).toBeVisible();
	await page.getByRole("link", { name: "Тестовая" }).click();
	await expect(page).toHaveURL(COLLECTION_DETAIL_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Тестовая" }),
	).toBeVisible();
	await expect(page.getByText("В коллекции пока нет медиа")).toBeVisible();
	await expect(page.getByRole("link", { name: "Сезон 1" })).toBeVisible();
	await page.getByRole("link", { name: "Сезон 1" }).click();
	await expect(page).toHaveURL(NESTED_COLLECTION_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Сезон 1" }),
	).toBeVisible();
	// biome-ignore lint/security/noSecrets: текст интерфейса, не секрет.
	await page.getByRole("button", { name: "Назад к «Тестовая»" }).click();
	await expect(page).toHaveURL(COLLECTION_DETAIL_PATTERN);
});

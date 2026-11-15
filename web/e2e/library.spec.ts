import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const VIDEO_LIST_PATTERN = /\/video$/;
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

test("коллекция переезжает в корень", async ({ page }) => {
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
	const collections = [
		{
			id: 1,
			user_id: 1,
			name: "Корень",
			type: "video",
			parent_id: null,
			created_at: "2026-01-01T00:00:00Z",
			updated_at: "2026-01-01T00:00:00Z",
		},
		{
			id: 2,
			user_id: 1,
			name: "Вложенная",
			type: "video",
			parent_id: 1,
			created_at: "2026-01-01T00:00:00Z",
			updated_at: "2026-01-01T00:00:00Z",
		},
	];
	await page.route(
		(url) => url.pathname === "/api/collections",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(collections),
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
	let moveBody = "";
	await page.route(
		(url) => url.pathname === "/api/collections/2",
		(route) => {
			moveBody = route.request().postData() ?? "";
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ ...collections[1], parent_id: null }),
			});
		},
	);

	await page.goto("/collections/2");
	await expect(
		page.getByRole("heading", { level: 1, name: "Вложенная" }),
	).toBeVisible();
	await page.getByRole("button", { name: "Действия" }).click();
	await page.getByRole("menuitem", { name: "Переместить коллекцию" }).click();
	await page.getByRole("button", { name: "В корень" }).click();

	expect(JSON.parse(moveBody)).toEqual({ parent_id: null });
	// Шапка устарела после переезда — уходим к списку раздела.
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
});

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

test("избранное: добавить и убрать; legacy-коллекции скрыты", async ({
	page,
}) => {
	await stubLibrary(page);
	let collectionRequests = 0;
	page.on("request", (request) => {
		if (new URL(request.url()).pathname.startsWith("/api/collections")) {
			collectionRequests += 1;
		}
	});

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

	// Legacy-коллекции скрыты из основных разделов.
	for (const [path, heading] of [
		["/video", "Видео"],
		["/audio", "Аудио"],
		["/memes", "Мемы"],
	] as const) {
		await page.goto(path);
		await expect(page.getByRole("heading", { name: heading })).toBeVisible();
		await expect(page.getByRole("heading", { name: "Коллекции" })).toHaveCount(
			0,
		);
		await expect(
			page.getByRole("button", { name: "Создать коллекцию" }),
		).toHaveCount(0);
	}
	expect(collectionRequests).toBe(0);
});

test("upload: админ не видит legacy-коллекции", async ({ page }) => {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 1,
				email: "admin@example.com",
				is_admin: true,
			}),
		}),
	);
	await stubEmptyLibraryMeta(page);
	let collectionRequests = 0;
	page.on("request", (request) => {
		if (new URL(request.url()).pathname.startsWith("/api/collections")) {
			collectionRequests += 1;
		}
	});
	await page.goto("/upload?type=video");
	await expect(page.getByRole("heading", { name: "Загрузка" })).toBeVisible();
	await expect(page.getByRole("combobox", { name: "Коллекция" })).toHaveCount(
		0,
	);
	await expect(
		page.getByRole("button", { name: "Создать коллекцию" }),
	).toHaveCount(0);
	await expect.poll(() => collectionRequests).toBe(0);
});

import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

// Клиентский переход TanStack Router сначала меняет URL, а страницу списка
// держит до коммита новой: в этот момент кнопок «Слушать» несколько (по одной
// на карточку). Поэтому ждём уникальный заголовок детальной страницы.

const userBody = JSON.stringify({
	id: 1,
	email: "user@example.com",
	is_admin: false,
});

function audioItem(id: number, title: string) {
	return {
		id,
		title,
		year: 2024,
		description: `Описание ${title}`,
		type: "audio",
		artists: [
			{ id: 1, name: "Исполнитель Один" },
			{ id: 2, name: "Исполнитель Два" },
		],
		album: "Альбом Один",
		genre: "Рок",
		duration: 225,
		width: 0,
		height: 0,
		file_size: 100,
		thumbnail_url: "",
		cover_url: `/api/media/${id}/cover`,
		view_count: 3,
		created_at: "2026-01-01T00:00:00Z",
	};
}

function listBody(items: ReturnType<typeof audioItem>[], total: number) {
	return JSON.stringify({ items, total, limit: 24, offset: 0 });
}

// 1×1 прозрачный PNG: обложка должна декодироваться как настоящая картинка.
const PIXEL_PNG = Buffer.from(
	// biome-ignore lint/security/noSecrets: это картинка-фикстура, а не секрет.
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
	"base64",
);

async function stubAuthedSession(page: Page) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: userBody,
		}),
	);
	await stubEmptyLibraryMeta(page);
}
async function stubAudioApi(page: Page) {
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) => {
			const url = new URL(route.request().url());
			const q = url.searchParams.get("q") ?? "";
			const type = url.searchParams.get("type");
			const all =
				type === "audio"
					? [audioItem(1, "Первая песня"), audioItem(2, "Вторая песня")]
					: [];
			const items = q === "" ? all : [];
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: listBody(items, items.length),
			});
		},
	);
	await page.route("**/api/media/1", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(audioItem(1, "Первая песня")),
		}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/cover",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "image/png",
				body: PIXEL_PNG,
			}),
	);
	// Реального файла нет: фиксируем ошибку потока, чтобы страница не
	// зависела от живого бэкенда.
	await page.route(
		(url) => url.pathname === "/api/media/1/stream",
		(route) =>
			route.fulfill({
				status: 404,
				contentType: "text/plain",
				body: "no stream",
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
	await page.route("**/api/progress/1", (route) =>
		route.fulfill({
			status: 404,
			contentType: "application/json",
			body: JSON.stringify({ error: "not found" }),
		}),
	);
}

test("страница артиста: треки и переименование", async ({ page }) => {
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
	await stubAudioApi(page);
	const artists = [
		{ id: 1, name: "Исполнитель Один" },
		{ id: 2, name: "Исполнитель Два" },
	];
	await page.route(
		(url) => url.pathname === "/api/artists",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: artists,
				}),
			}),
	);
	let renameBody = "";
	await page.route(
		(url) => url.pathname === "/api/artists/1",
		(route) => {
			renameBody = route.request().postData() ?? "";
			artists[0] = { id: 1, name: "Переименованный" };
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ id: 1, name: "Переименованный" }),
			});
		},
	);

	await page.goto("/artists/1");
	await expect(
		page.getByRole("heading", { level: 1, name: "Исполнитель Один" }),
	).toBeVisible();
	await expect(page.getByText("Первая песня")).toBeVisible();
	await expect(page.getByText("Вторая песня")).toBeVisible();

	await page.getByRole("button", { name: "Переименовать" }).click();
	await page.getByLabel("Имя исполнителя").fill("Переименованный");
	await page.getByRole("button", { name: "Сохранить" }).click();

	expect(JSON.parse(renameBody)).toEqual({ name: "Переименованный" });
	await expect(
		page.getByRole("heading", { level: 1, name: "Переименованный" }),
	).toBeVisible();
});

test("избранные артисты: секция в списке и сердечки на детальной", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubAudioApi(page);
	let artistFavs = [1];
	const artistFavsBody = () =>
		JSON.stringify({
			items: artistFavs.map((artistId) => ({
				id: 100 + artistId,
				user_id: 1,
				media_id: null,
				artist_id: artistId,
				media: null,
				created_at: "2026-01-01T00:00:00Z",
			})),
			total: artistFavs.length,
			limit: 200,
			offset: 0,
		});
	// Регистрируется после stubAuthedSession и перехватывает первой:
	// с type — медиа-избранное, без — артисты.
	await page.route(
		(url) => url.pathname === "/api/favorites",
		(route) => {
			const params = new URL(route.request().url()).searchParams;
			if (params.has("type")) {
				return route.fulfill({
					status: 200,
					contentType: "application/json",
					body: JSON.stringify({ items: [], total: 0, limit: 200, offset: 0 }),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: artistFavsBody(),
			});
		},
	);
	await page.route(
		(url) => url.pathname === "/api/artists",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [
						{ id: 1, name: "Исполнитель Один" },
						{ id: 2, name: "Исполнитель Два" },
					],
				}),
			}),
	);
	const artistRequests: string[] = [];
	await page.route(
		(url) => url.pathname === "/api/favorites/artist",
		(route) => {
			const method = route.request().method();
			if (method === "POST") {
				artistFavs = [...artistFavs, 2];
				artistRequests.push(`POST ${route.request().postData() ?? ""}`);
				return route.fulfill({
					status: 201,
					contentType: "application/json",
					body: JSON.stringify({ id: 102, user_id: 1, artist_id: 2 }),
				});
			}
			const artistId = Number(
				new URL(route.request().url()).searchParams.get("artist_id"),
			);
			artistFavs = artistFavs.filter((id) => id !== artistId);
			artistRequests.push(`DELETE artist_id=${artistId}`);
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ message: "removed" }),
			});
		},
	);

	await page.goto("/audio");
	await expect(
		page.getByRole("heading", { name: "Избранные исполнители" }),
	).toBeVisible();
	await expect(
		page.getByText("Исполнитель Один", { exact: true }),
	).toBeVisible();

	// Клик по чипу ищет треки исполнителя.
	await page.getByText("Исполнитель Один", { exact: true }).click();
	await expect(
		page.getByLabel("Поиск по названию, альбому или исполнителю"),
	).toHaveValue("Исполнитель Один");

	await page.goto("/artists/1");
	await expect(
		page.getByRole("heading", { level: 1, name: "Исполнитель Один" }),
	).toBeVisible();
	const removeHeart = page.getByRole("button", {
		name: "Убрать из избранного: Исполнитель Один",
	});
	await expect(removeHeart).toBeVisible();
	await removeHeart.click();
	await expect
		.poll(() => artistRequests.some((entry) => entry === "DELETE artist_id=1"))
		.toBe(true);
	await expect(
		page.getByRole("button", {
			name: "Добавить в избранное: Исполнитель Один",
		}),
	).toBeVisible();
});

test("страница артиста: ошибка треков и исполнителя с повтором", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubEmptyLibraryMeta(page);
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 500,
				contentType: "application/json",
				body: JSON.stringify({ error: "boom" }),
			}),
	);
	let artistsCalls = 0;
	await page.route(
		(url) => url.pathname === "/api/artists",
		(route) => {
			artistsCalls += 1;
			if (artistsCalls === 1) {
				return route.fulfill({
					status: 500,
					contentType: "application/json",
					body: JSON.stringify({ error: "boom" }),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [{ id: 1, name: "Исполнитель Один" }],
				}),
			});
		},
	);

	await page.goto("/artists/1");
	await expect(
		page.getByText("Не удалось загрузить исполнителя"),
	).toBeVisible();
	await page.getByRole("button", { name: "Повторить" }).click();
	// Справочник поднялся, а список треков лежит: видна его ошибка.
	await expect(
		page.getByRole("heading", { level: 1, name: "Исполнитель Один" }),
	).toBeVisible();
	await expect(page.getByText("Не удалось загрузить треки")).toBeVisible();
});

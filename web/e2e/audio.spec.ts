import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const AUDIO_LIST_PATTERN = /\/audio$/;
const AUDIO_DETAIL_PATTERN = /\/audio\/1$/;

// Клиентский переход TanStack Router сначала меняет URL, а страницу списка
// держит до коммита новой: в этот момент кнопок «Слушать» несколько (по одной
// на карточку). Поэтому ждём уникальный заголовок детальной страницы.
async function expectAudioDetail(page: Page): Promise<void> {
	await expect(page).toHaveURL(AUDIO_DETAIL_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Первая песня" }),
	).toBeVisible();
	await expect(page.getByRole("button", { name: "Слушать" })).toHaveCount(1);
}

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

function progressItem(
	id: number,
	media: ReturnType<typeof audioItem>,
	position: number,
	completed = false,
) {
	return {
		id,
		user_id: 1,
		media_id: media.id,
		position,
		duration: media.duration,
		completed,
		updated_at: "2026-01-01T00:00:00Z",
		media,
	};
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

test("аудио: список, поиск и переход в детали с плеером", async ({ page }) => {
	await stubAuthedSession(page);
	await stubAudioApi(page);

	await page.goto("/audio");

	await expect(
		page.getByRole("heading", { level: 1, name: "Аудио" }),
	).toBeVisible();
	await expect(page.getByText("Первая песня", { exact: true })).toBeVisible();
	await expect(page.getByText("Вторая песня", { exact: true })).toBeVisible();
	await expect(
		page.getByText("Исполнитель Один, Исполнитель Два").first(),
	).toBeVisible();

	await page
		.getByLabel("Поиск по названию, альбому или исполнителю")
		.fill("небылица");
	await expect(page.getByText("Ничего не найдено")).toBeVisible();

	await page.getByLabel("Поиск по названию, альбому или исполнителю").fill("");
	await expect(page.getByText("Первая песня", { exact: true })).toBeVisible();

	await page.getByRole("link", { name: "Первая песня" }).click();
	await expectAudioDetail(page);
	await expect(
		page.getByText("Исполнитель Один", { exact: true }),
	).toBeVisible();
	await expect(
		page.getByText("Исполнитель Два", { exact: true }),
	).toBeVisible();
	await expect(page.getByText("Альбом Один")).toBeVisible();
	await expect(page.getByText("Рок")).toBeVisible();
	await expect(page.getByText("3:45")).toBeVisible();
	await expect(page.getByText("Описание Первая песня")).toBeVisible();
	// Обложка — декоративный фон, отдельного <img> на странице нет.
	await expect(page.locator('div[style*="/api/media/1/cover"]')).toHaveCount(1);
});

test("аудио: недослушанный трек поднимается мини-плеером на паузе", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubAudioApi(page);
	await page.route(
		(url) => url.pathname === "/api/progress",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [progressItem(2, audioItem(2, "Вторая песня"), 40)],
					total: 1,
					limit: 20,
					offset: 0,
				}),
			}),
	);

	await page.goto("/audio");
	// Блока продолжения в разделе нет: вместо него мини-плеер с треком.
	await expect(
		page.getByRole("heading", {
			// biome-ignore lint/security/noSecrets: текст интерфейса, не секрет.
			name: "Продолжить прослушивание",
		}),
	).toHaveCount(0);
	const miniPlayer = page.locator(".audio-mini-player");
	await expect(miniPlayer).toBeVisible();
	await expect(miniPlayer.getByText("Вторая песня")).toBeVisible();
	// Стоит на паузе: показана кнопка старта, а не паузы.
	await expect(
		miniPlayer.getByRole("button", { name: "Слушать" }),
	).toBeVisible();
});

test("аудио открывается из навигации", async ({ page }) => {
	await stubAuthedSession(page);
	await stubAudioApi(page);
	await page.route("**/api/health", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ status: "ok", version: "1.0.8" }),
		}),
	);

	await page.goto("/");
	await page.getByRole("link", { name: "Аудио" }).click();
	await expect(page).toHaveURL(AUDIO_LIST_PATTERN);
});

test("админ удаляет трек из списка", async ({ page }) => {
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
	const items = [audioItem(1, "Первая песня"), audioItem(2, "Вторая песня")];
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: listBody(items, items.length),
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
	let deletedId = 0;
	await page.route(
		(url) => url.pathname === "/api/media/1",
		(route) => {
			if (route.request().method() === "DELETE") {
				deletedId = 1;
				items.shift();
				return route.fulfill({
					status: 200,
					contentType: "application/json",
					body: JSON.stringify({ message: "Media moved to trash" }),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(audioItem(1, "Первая песня")),
			});
		},
	);

	await page.goto("/audio");
	await expect(page.getByText("Первая песня", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Удалить" }).first().click();
	await page
		.getByRole("dialog")
		.getByRole("button", { name: "Удалить" })
		.click();

	expect(deletedId).toBe(1);
	await expect(page.getByText("Первая песня", { exact: true })).toBeHidden();
	await expect(page.getByText("Вторая песня", { exact: true })).toBeVisible();
});

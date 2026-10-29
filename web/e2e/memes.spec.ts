import { expect, type Page, test } from "@playwright/test";

const MEMES_LIST_PATTERN = /\/memes$/;
const MEME_DETAIL_PATTERN = /\/memes\/1$/;
const UPLOAD_IMAGE_PATTERN = /\/upload\?type=image$/;
// biome-ignore lint/security/noSecrets: CSS-селектор, не секрет.
const FILE_INPUT_SELECTOR = 'input[type="file"]';

function sessionBody(isAdmin: boolean): string {
	return JSON.stringify({
		id: 1,
		email: "user@example.com",
		is_admin: isAdmin,
	});
}

function imageItem(id: number, title: string) {
	return {
		id,
		title,
		filename: `meme-${id}.png`,
		year: 0,
		description: `Описание ${title}`,
		type: "image",
		artists: [],
		album: "",
		genre: "",
		duration: 0,
		width: 800,
		height: 600,
		file_size: 1234,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: "",
		view_count: 1,
		created_at: "2026-01-01T00:00:00Z",
	};
}

function listBody(items: ReturnType<typeof imageItem>[], total: number) {
	return JSON.stringify({ items, total, limit: 24, offset: 0 });
}

// 1×1 прозрачный PNG: превью и оригинал должны декодироваться.
const PIXEL_PNG = Buffer.from(
	// biome-ignore lint/security/noSecrets: это картинка-фикстура, а не секрет.
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
	"base64",
);

async function stubAuthedSession(page: Page, isAdmin = false) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: sessionBody(isAdmin),
		}),
	);
}

// Список отдаёт мемы только при type=image&sort=desc: так тест ловит
// и правильный тип запроса, и сортировку «новые сверху».
async function stubMemesApi(page: Page) {
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) => {
			const url = new URL(route.request().url());
			const q = url.searchParams.get("q") ?? "";
			const type = url.searchParams.get("type");
			const sort = url.searchParams.get("sort");
			const all =
				type === "image" && sort === "desc"
					? [imageItem(1, "Первый мем"), imageItem(2, "Второй мем")]
					: [];
			const items = q === "" ? all : [];
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: listBody(items, items.length),
			});
		},
	);
	await page.route(
		(url) => url.pathname === "/api/media/1",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(imageItem(1, "Первый мем")),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/thumb",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "image/png",
				body: PIXEL_PNG,
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/stream",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "image/png",
				body: PIXEL_PNG,
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
}

test("мемы: сетка, поиск, просмотрщик и скачивание", async ({ page }) => {
	await stubAuthedSession(page);
	await stubMemesApi(page);

	await page.goto("/memes");

	await expect(
		page.getByRole("heading", { level: 1, name: "Мемы" }),
	).toBeVisible();
	await expect(page.getByRole("link", { name: "Первый мем" })).toBeVisible();
	await expect(page.locator('img[src="/api/media/1/thumb"]')).toBeVisible();
	await expect(page.getByRole("link", { name: "Второй мем" })).toBeVisible();
	// Не админ не видит кнопку загрузки.
	await expect(page.locator(FILE_INPUT_SELECTOR)).toHaveCount(0);

	await page.getByLabel("Поиск по названию").fill("небылица");
	await expect(page.getByText("Ничего не найдено")).toBeVisible();

	await page.getByLabel("Поиск по названию").fill("");
	await expect(page.getByRole("link", { name: "Первый мем" })).toBeVisible();

	await page.getByRole("link", { name: "Первый мем" }).click();
	await expect(page).toHaveURL(MEME_DETAIL_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Первый мем" }),
	).toBeVisible();
	await expect(page.locator('img[src="/api/media/1/stream"]')).toBeVisible();
	await expect(page.getByRole("link", { name: "Скачать" })).toHaveAttribute(
		"download",
		"meme-1.png",
	);

	await page.getByRole("button", { name: "К мемам" }).click();
	await expect(page).toHaveURL(MEMES_LIST_PATTERN);
});

test("мемы открываются из навигации", async ({ page }) => {
	await stubAuthedSession(page);
	await stubMemesApi(page);
	await page.route("**/api/health", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ status: "ok", version: "1.0.14" }),
		}),
	);

	await page.goto("/");
	await page.getByRole("link", { name: "Мемы" }).click();
	await expect(page).toHaveURL(MEMES_LIST_PATTERN);
});

test("мемы: админ видит похожий мем и может добавить поверх", async ({
	page,
}) => {
	await stubAuthedSession(page, true);
	await stubMemesApi(page);

	const uploadBodies: string[] = [];
	await page.route(
		(url) => url.pathname === "/api/media/upload",
		(route) => {
			uploadBodies.push(route.request().postDataBuffer()?.toString() ?? "");
			return route.fulfill({
				status: 202,
				contentType: "application/json",
				body: JSON.stringify({
					job_id: uploadBodies.length,
					job_type: "upload",
				}),
			});
		},
	);
	await page.route(
		(url) => url.pathname === "/api/media/uploads/1",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					id: 1,
					status: "duplicate",
					error: null,
					media: null,
					duplicate: { id: 9, title: "Старый мем" },
				}),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/uploads/2",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					id: 2,
					status: "done",
					error: null,
					media: imageItem(3, "Новый мем"),
				}),
			}),
	);

	await page.goto("/memes");
	await page.getByRole("button", { name: "Загрузить мем" }).click();
	await expect(page).toHaveURL(UPLOAD_IMAGE_PATTERN);
	await page.locator(FILE_INPUT_SELECTOR).setInputFiles({
		name: "new.png",
		mimeType: "image/png",
		buffer: PIXEL_PNG,
	});

	await expect(page.getByText("Похоже, уже есть: Старый мем")).toBeVisible();
	expect(uploadBodies[0]).toContain('name="media_type"');
	expect(uploadBodies[0]).toContain("image");

	await page.getByRole("button", { name: "Всё равно добавить" }).click();
	await expect(page.getByText("Готово", { exact: false })).toBeVisible();
	expect(uploadBodies[1]).toContain('name="force"');
	expect(uploadBodies[1]).toContain("true");

	await page.getByRole("button", { name: "Назад" }).click();
	await expect(page).toHaveURL(MEMES_LIST_PATTERN);
	await expect(page.getByRole("link", { name: "Первый мем" })).toBeVisible();
});

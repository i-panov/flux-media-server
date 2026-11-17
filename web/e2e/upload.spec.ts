import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

// biome-ignore lint/security/noSecrets: CSS-селектор, не секрет.
const FILE_INPUT_SELECTOR = 'input[type="file"]';
const UPLOAD_VIDEO_PATTERN = /\/upload\?type=video$/;

function sessionBody(isAdmin: boolean): string {
	return JSON.stringify({
		id: 1,
		email: "user@example.com",
		is_admin: isAdmin,
	});
}

async function stubSession(page: Page, isAdmin: boolean) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: sessionBody(isAdmin),
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
	await stubEmptyLibraryMeta(page);
}

test("загрузка видео показывает прогресс нормализации", async ({ page }) => {
	await stubSession(page, true);
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 24, offset: 0 }),
			}),
	);

	let uploadBody = "";
	await page.route(
		(url) => url.pathname === "/api/media/upload",
		(route) => {
			uploadBody = route.request().postDataBuffer()?.toString() ?? "";
			return route.fulfill({
				status: 202,
				contentType: "application/json",
				body: JSON.stringify({ job_id: 5, job_type: "transcode" }),
			});
		},
	);
	let polls = 0;
	await page.route(
		(url) => url.pathname === "/api/media/transcodes/5",
		(route) => {
			polls += 1;
			const done = polls > 1;
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					id: 5,
					status: done ? "done" : "processing",
					error: null,
					media: null,
					progress: done ? 100 : 40,
				}),
			});
		},
	);

	await page.goto("/video");
	await page.getByRole("button", { name: "Загрузить видео" }).click();
	await expect(page).toHaveURL(UPLOAD_VIDEO_PATTERN);

	await page.locator(FILE_INPUT_SELECTOR).setInputFiles({
		name: "movie.mp4",
		mimeType: "video/mp4",
		buffer: Buffer.from("fake video"),
	});

	await expect(page.getByText("Обработка на сервере...")).toBeVisible();
	await expect(page.getByText("Готово", { exact: false })).toBeVisible({
		timeout: 10_000,
	});
	expect(uploadBody).toContain('name="media_type"');
	expect(uploadBody).toContain("video");
});

test("загрузка недоступна обычному пользователю", async ({ page }) => {
	await stubSession(page, false);

	await page.goto("/upload?type=video");
	await expect(
		page.getByText("Загрузка доступна только администратору"),
	).toBeVisible();
});

const SELECTED_BUTTON = /Скачать выбранное/;
const IMPORT_DONE = /Готово 3 из 3/;

test("импорт сериала: проверка ссылки и выбор серий", async ({ page }) => {
	await stubSession(page, true);
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 24, offset: 0 }),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/import/probe",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					kind: "series",
					series_id: "rutube:1",
					title: "Тестовый сериал",
					scope: "series",
					seasons: [1, 2],
					episodes: [
						{ season: 1, episode: 1, title: "Первая", duration: 100 },
						{ season: 1, episode: 2, title: "Вторая", duration: 100 },
						{ season: 2, episode: 1, title: "Третья", duration: 100 },
					],
				}),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/import",
		(route) => {
			if (route.request().method() === "GET") {
				return route.fulfill({
					status: 200,
					contentType: "application/json",
					body: "[]",
				});
			}
			return route.fulfill({
				status: 202,
				contentType: "application/json",
				body: JSON.stringify({
					id: 7,
					source_url: "https://rutube.ru/video/1/",
					scope: "series",
					title: "Тестовый сериал",
					status: "queued",
					episodes_total: 3,
					episodes_done: 0,
					episodes_error: 0,
				}),
			});
		},
	);
	await page.route(
		(url) => url.pathname === "/api/import/7",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					job: {
						id: 7,
						source_url: "https://rutube.ru/video/1/",
						scope: "series",
						title: "Тестовый сериал",
						status: "done",
						episodes_total: 3,
						episodes_done: 3,
						episodes_error: 0,
					},
					episodes: [
						{ id: 1, season: 1, episode: 1, title: "Первая", status: "done" },
						{ id: 2, season: 1, episode: 2, title: "Вторая", status: "done" },
						{ id: 3, season: 2, episode: 1, title: "Третья", status: "done" },
					],
				}),
			}),
	);

	await page.goto("/video");
	await page.getByRole("button", { name: "Загрузить видео" }).click();
	await expect(page).toHaveURL(UPLOAD_VIDEO_PATTERN);
	await expect(
		page.getByText("Импорт сезона по ссылке", { exact: true }),
	).toBeVisible();
	await page.getByTestId("import-url").fill("https://rutube.ru/video/1/");
	await page.getByRole("button", { name: "Проверить" }).click();
	await expect(
		page.getByText("Тестовый сериал", { exact: true }),
	).toBeVisible();
	await expect(page.getByRole("checkbox")).toHaveCount(3);
	await page.getByRole("button", { name: SELECTED_BUTTON }).click();
	await expect(page.getByText(IMPORT_DONE)).toBeVisible();
});

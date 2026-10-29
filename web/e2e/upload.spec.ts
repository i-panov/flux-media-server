import { expect, type Page, test } from "@playwright/test";

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

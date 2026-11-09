import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const HOME_URL_PATTERN = /\/$/;

function sessionBody(isAdmin: boolean): string {
	return JSON.stringify({
		id: 1,
		email: "admin@example.com",
		is_admin: isAdmin,
	});
}

async function stubAdmin(page: Page, isAdmin: boolean) {
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
	await page.route(
		(url) => url.pathname === "/api/admin/storage",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					disks: [{ path: "/data", total_bytes: 1000, free_bytes: 50 }],
					video_bytes: 10,
					audio_bytes: 20,
					originals_bytes: 30,
					temp_bytes: 40,
					auto_cleanup: true,
				}),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/admin/transcodes",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify([
					{
						id: 2,
						status: "error",
						progress: 40,
						speed: 0,
						eta_seconds: 0,
						error: "ffmpeg failed",
						filename: "movie.mp4",
						media_id: 3,
					},
				]),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/admin/originals",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify([
					{
						name: "movie.mp4",
						size_bytes: 100,
						modified: "2026-01-01T00:00:00Z",
						status: "done",
						media_id: 3,
						views: 5,
					},
				]),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/admin/users",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify([
					{
						id: 1,
						email: "admin@example.com",
						is_admin: true,
						created_at: "2026-01-01T00:00:00Z",
					},
					{
						id: 2,
						email: "user@example.com",
						is_admin: false,
						created_at: "2026-01-02T00:00:00Z",
					},
				]),
			}),
	);
}

test("админка показывает все секции", async ({ page }) => {
	await stubAdmin(page, true);
	await page.goto("/admin");

	await expect(
		page.getByRole("heading", { level: 1, name: "Администрирование" }),
	).toBeVisible();
	await expect(page.getByRole("heading", { name: "Хранилище" })).toBeVisible();
	await expect(
		page.getByRole("heading", { name: "Очередь транскодирования" }),
	).toBeVisible();
	await expect(
		page.getByRole("heading", { name: "Карантин оригиналов" }),
	).toBeVisible();
	await expect(
		page.getByRole("heading", { name: "Пользователи" }),
	).toBeVisible();
	await expect(page.getByText("movie.mp4").first()).toBeVisible();
	await expect(page.getByText("user@example.com")).toBeVisible();
	await expect(
		page.getByRole("link", { name: "Админка" }).first(),
	).toBeVisible();
});

test("админка недоступна обычному пользователю", async ({ page }) => {
	await stubAdmin(page, false);
	await page.goto("/admin");

	// beforeLoad-guard уводит обычного пользователя на главную.
	await expect(page).toHaveURL(HOME_URL_PATTERN);
	await expect(page.getByRole("heading", { name: "Пользователи" })).toHaveCount(
		0,
	);
	await expect(page.getByRole("link", { name: "Админка" })).toHaveCount(0);
});

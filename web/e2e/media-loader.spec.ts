import { readFileSync } from "node:fs";
import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const VIDEO = readFileSync(new URL("./fixtures/video.mp4", import.meta.url));
const PIXEL = Buffer.from(
	// biome-ignore lint/security/noSecrets: PNG-фикстура, не секрет.
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
	"base64",
);

const TITLE_PATTERN = /Новый ролик/;
const VIDEO_URL_PATTERN = /\/video\/42$/;

const mediaItem = {
	id: 42,
	title: "Новый ролик",
	year: 2026,
	description: "Загружен по ссылке",
	type: "video",
	duration: 1,
	width: 320,
	height: 180,
	file_size: VIDEO.length,
	thumbnail_url: "/api/media/42/thumb",
	cover_url: "",
	view_count: 0,
	created_at: "2026-01-01T00:00:00Z",
	source_url: "https://example.com/video",
};

async function stubAdmin(page: Page) {
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
}

test("загрузка по ссылке: done уходит из очереди, карточка играет", async ({
	page,
}) => {
	await stubAdmin(page);
	let started = false;
	let done = false;
	const job = {
		id: "loader-1",
		status: "downloading",
		stage: "downloading",
		progress: 40,
		title: "Новый ролик",
	};

	await page.route(
		(url) => url.pathname === "/api/admin/downloads",
		(route) => {
			if (route.request().method() === "POST") {
				started = true;
				setTimeout(() => {
					done = true;
				}, 400);
				return route.fulfill({
					status: 202,
					contentType: "application/json",
					body: JSON.stringify(job),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(done ? [] : started ? [job] : []),
			});
		},
	);

	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: done ? [mediaItem] : [],
					total: done ? 1 : 0,
					limit: 24,
					offset: 0,
				}),
			}),
	);
	await page.route("**/api/media/42/stream", (route) =>
		route.fulfill({
			status: 200,
			headers: { "Content-Type": "video/mp4", "Accept-Ranges": "bytes" },
			body: VIDEO,
		}),
	);
	await page.route("**/api/media/42", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(mediaItem),
		}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/42/thumb",
		(route) =>
			route.fulfill({ status: 200, contentType: "image/png", body: PIXEL }),
	);
	await page.route(
		(url) => url.pathname === "/api/media/42/subs",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: "[]",
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/progress/42",
		(route) =>
			route.fulfill({
				status: 404,
				contentType: "application/json",
				body: JSON.stringify({ error: "not found" }),
			}),
	);

	await page.goto("/upload?type=video");
	await page.getByTestId("upload-link-url").fill("https://example.com/video");
	await page.getByTestId("upload-link-submit").click();

	// Пока задание активно, оно видно в очереди.
	await expect(page.getByTestId("upload-link-job")).toBeVisible();
	await expect(page.getByText("40%")).toBeVisible();
	// После done backend больше не отдаёт его в списке.
	await expect(page.getByTestId("upload-link-job")).toHaveCount(0, {
		timeout: 5_000,
	});

	await page.goto("/video");
	await page.getByRole("link", { name: TITLE_PATTERN }).click();
	await expect(page).toHaveURL(VIDEO_URL_PATTERN);
	await expect(page.locator("video")).toBeVisible();

	await expect
		.poll(
			() =>
				page.locator("video").evaluate((element) => {
					const video = element as HTMLVideoElement;
					return video.readyState;
				}),
			{ timeout: 5_000 },
		)
		.toBeGreaterThanOrEqual(2);
	await expect(page.getByText("Не удалось загрузить видео")).toHaveCount(0);
});

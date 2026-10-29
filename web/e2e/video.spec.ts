import { expect, type Page, test } from "@playwright/test";

const VIDEO_LIST_PATTERN = /\/video$/;
const VIDEO_DETAIL_PATTERN = /\/video\/1$/;

const userBody = JSON.stringify({
	id: 1,
	email: "user@example.com",
	is_admin: false,
});

function videoItem(id: number, title: string) {
	return {
		id,
		title,
		year: 2024,
		description: `Описание ${title}`,
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

async function stubAuthedSession(page: Page) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: userBody,
		}),
	);
}

async function stubVideoApi(page: Page) {
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) => {
			const url = new URL(route.request().url());
			const q = url.searchParams.get("q") ?? "";
			const items =
				q === ""
					? [videoItem(1, "Первый фильм"), videoItem(2, "Второй фильм")]
					: [];
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
			body: JSON.stringify(videoItem(1, "Первый фильм")),
		}),
	);
	await page.route("**/api/media/1/subs", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify([{ lang: "ru", url: "/api/media/1/subs/ru" }]),
		}),
	);
}

test("видео: список, поиск и переход в детали с плеером", async ({ page }) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);

	await page.goto("/video");

	await expect(
		page.getByRole("heading", { level: 1, name: "Видео" }),
	).toBeVisible();
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();
	await expect(page.getByText("Второй фильм", { exact: true })).toBeVisible();

	await page.getByLabel("Поиск по названию").fill("небылица");
	await expect(page.getByText("Ничего не найдено")).toBeVisible();

	await page.getByLabel("Поиск по названию").fill("");
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();

	await page.getByRole("link", { name: "Первый фильм" }).click();
	await expect(page).toHaveURL(VIDEO_DETAIL_PATTERN);
	await expect(page.locator("video")).toBeVisible();
	await expect(page.getByText("Описание Первый фильм")).toBeVisible();
	await expect(page.getByText("1:02:05")).toBeVisible();
});

test("видео открывается из навигации", async ({ page }) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await page.route("**/api/health", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ status: "ok", version: "1.0.8" }),
		}),
	);

	await page.goto("/");
	await page.getByRole("link", { name: "Видео" }).click();
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
});

test("видео: 401 потока и деталей чинится повтором после refresh", async ({
	page,
}) => {
	await stubAuthedSession(page);
	let streamHits = 0;
	let mediaHits = 0;
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: listBody([videoItem(1, "Первый фильм")], 1),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1",
		(route) => {
			mediaHits += 1;
			// Первый запрос застаёт истёкшую сессию: apiFetch сам
			// обновит её через /api/auth/refresh и повторит.
			if (mediaHits === 1) {
				return route.fulfill({
					status: 401,
					contentType: "application/json",
					body: JSON.stringify({ error: "expired" }),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(videoItem(1, "Первый фильм")),
			});
		},
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/subs",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: "[]",
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/stream",
		(route) => {
			streamHits += 1;
			if (streamHits === 1) {
				return route.fulfill({
					status: 401,
					contentType: "application/json",
					body: JSON.stringify({ error: "expired" }),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "video/mp4",
				body: "",
			});
		},
	);
	await page.route("**/api/auth/refresh", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: "{}",
		}),
	);

	await page.goto("/video/1");
	// Страница отрендерилась, пережив 401 деталей, а плеер запросил
	// поток заново после 401 — восстановление с двух сторон.
	await expect(page.locator("video")).toBeVisible();
	await expect
		.poll(() => streamHits, { timeout: 15_000 })
		.toBeGreaterThanOrEqual(2);
});

test("видео: ошибка дорожки ведёт к перемонтированию плеера", async ({
	page,
}) => {
	await stubAuthedSession(page);
	let streamHits = 0;
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: listBody([videoItem(1, "Первый фильм")], 1),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(videoItem(1, "Первый фильм")),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/subs",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify([{ lang: "ru", url: "/api/media/1/subs/ru" }]),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/subs/ru",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "text/vtt",
				body: "WEBVTT\n\n00:00.000 --> 00:01.000\nHi",
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/stream",
		() => {
			// Поток висит без ответа: video-ошибка не стреляет и не
			// мешает изолировать трек-путь (иначе сработал бы tried-гард).
			streamHits += 1;
			return new Promise<void>(() => {});
		},
	);

	await page.goto("/video/1");
	await expect(page.locator("video")).toBeVisible();
	await expect(page.locator("track")).toHaveCount(1);

	// Браузер не тянет отключённые дорожки сам — имитируем его событие
	// ошибки (истёкшая кука при включении субтитров из CC-меню).
	const dispatched = await page.evaluate(() => {
		const track = document.querySelector("track");
		if (track === null) {
			return false;
		}
		track.dispatchEvent(new Event("error"));
		return true;
	});
	expect(dispatched).toBe(true);

	// Ошибка дорожки прошла SubTrack → зонд → remount: поток запрошен
	// заново уже новым элементом video.
	await expect
		.poll(() => streamHits, { timeout: 15_000 })
		.toBeGreaterThanOrEqual(2);
});

test("видео: ошибка догрузки не скрывает загруженный список", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) => {
			const offset = new URL(route.request().url()).searchParams.get("offset");
			// Догрузка падает, первая страница всегда успешна —
			// независимо от порядка и дублей запросов в dev-режиме.
			if (offset !== "0") {
				return route.fulfill({
					status: 500,
					contentType: "application/json",
					body: JSON.stringify({ error: "boom" }),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: listBody([videoItem(1, "Первый фильм")], 3),
			});
		},
	);

	await page.goto("/video");
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Показать ещё" }).click();
	await expect(
		page.getByText("Не удалось загрузить список видео"),
	).toBeVisible();
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();
});

test("видео: сохранённая позиция восстанавливается при открытии", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	// Реального медиафайла нет: подменяем currentTime/duration, иначе
	// браузер бросает InvalidStateError на установку времени.
	await page.addInitScript(() => {
		let stored = 0;
		Object.defineProperty(HTMLMediaElement.prototype, "currentTime", {
			configurable: true,
			get() {
				return stored;
			},
			set(value: number) {
				stored = value;
			},
		});
		Object.defineProperty(HTMLMediaElement.prototype, "duration", {
			configurable: true,
			get() {
				return 3725;
			},
		});
	});
	await page.route("**/api/progress/1", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 1,
				user_id: 1,
				media_id: 1,
				position: 1200,
				duration: 3725,
				completed: false,
				updated_at: "2026-01-01T00:00:00Z",
			}),
		}),
	);
	// Медиафайла нет: фиксируем ошибку потока, чтобы поведение не зависело
	// от того, успел ли браузер запросить реальный /stream.
	await page.route("**/api/media/1/stream", (route) =>
		route.fulfill({
			status: 404,
			contentType: "text/plain",
			body: "no stream",
		}),
	);

	await page.goto("/video/1");
	const video = page.locator("video");
	await expect(video).toBeVisible();
	// Ошибка потока запускает зонд и перемонтирование плеера. Ждём, пока
	// попытки исчерпаются: иначе loadedmetadata может достаться элементу,
	// который тут же заменят, и восстановленная позиция потеряется.
	await expect(page.getByText("Не удалось загрузить видео")).toBeVisible();
	await video.evaluate((el) => el.dispatchEvent(new Event("loadedmetadata")));

	await expect
		.poll(() =>
			video.evaluate((el) => Number((el as HTMLVideoElement).currentTime)),
		)
		.toBe(1200);
});

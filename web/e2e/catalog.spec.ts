import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const SERIES_TITLE = /Тестовый сериал/;
const FRANCHISE_TITLE = /Тестовая франшиза/;
const FILM_SERIES_TITLE = /Тестовая серия фильмов/;
const PILOT_TITLE = /Пилот/;
const FILM_SERIES_LINK = /Тестовая серия фильмов/;
const FIRST_FILM_LINK = /Первый фильм/;
const FRANCHISE_MOVIE_LINK = /Полнометражный фильм/;
const FILM_SERIES_URL = /\/series\/9$/;
const SERIES_DETAIL_URL = /\/series\/9$/;

async function stubAuth(page: Page) {
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

function activeKey(page: Page) {
	return page.evaluate(() =>
		document.activeElement?.getAttribute("data-tv-focus-key"),
	);
}

const series = {
	id: 7,
	kind: "series",
	title: "Тестовый сериал",
	description: "Описание",
	cover_url: "",
	year: 2026,
};

const filmSeries = {
	id: 9,
	kind: "film_series",
	title: "Тестовая серия фильмов",
	description: "Фильмы",
	cover_url: "",
	year: 2025,
};

const season = {
	id: 11,
	work_id: 7,
	season_number: 1,
	title: "Сезон 1",
	position: 0,
	items: [
		{
			id: 21,
			season_id: 11,
			media_id: 42,
			position: 0,
			episode_number: 1,
			media: {
				id: 42,
				title: "Пилот",
				year: 2026,
				type: "video",
				duration: 60,
				thumbnail_url: "",
				cover_url: "",
			},
		},
	],
};

const franchise = {
	id: 3,
	name: "Тестовая франшиза",
	description: "Вселенная",
	cover_url: "",
};

const franchiseDetail = {
	...franchise,
	entries: [
		{ id: 1, franchise_id: 3, work_id: 7, position: 0, work: series },
		{ id: 2, franchise_id: 3, work_id: 9, position: 1, work: filmSeries },
		{
			id: 3,
			franchise_id: 3,
			media_id: 42,
			position: 2,
			media: { id: 42, title: "Полнометражный фильм", type: "video" },
		},
	],
};

async function stubCatalog(page: Page, delayMs = 0) {
	await stubAuth(page);
	await page.route(
		(url) => url.pathname === "/api/works",
		async (route) => {
			if (delayMs > 0) {
				await new Promise((resolve) => setTimeout(resolve, delayMs));
			}
			const kind = new URL(route.request().url()).searchParams.get("kind");
			const body =
				kind === "series"
					? [series]
					: kind === "film_series"
						? [filmSeries]
						: [];
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(body),
			});
		},
	);
	await page.route("**/api/works/7", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ ...series, seasons: [season] }),
		}),
	);
	await page.route("**/api/works/9", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				...filmSeries,
				items: [
					{
						id: 31,
						work_id: 9,
						media_id: 55,
						position: 0,
						media: { id: 55, title: "Первый фильм" },
					},
				],
			}),
		}),
	);
	await page.route("**/api/franchises", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify([franchise]),
		}),
	);
	await page.route("**/api/franchises/3", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(franchiseDetail),
		}),
	);
}

test("каталог: сериал с сезоном и эпизодом", async ({ page }) => {
	await stubCatalog(page);
	await page.goto("/series");
	await expect(
		page.getByRole("heading", { name: "Сериалы и фильмы" }),
	).toBeVisible();
	await page.getByRole("link", { name: SERIES_TITLE }).click();
	await expect(page.getByRole("heading", { name: "Сезон 1" })).toBeVisible();
	await expect(
		page.getByRole("link", { name: PILOT_TITLE }).first(),
	).toBeVisible();
});

test("каталог: film_series доступна вне франшизы", async ({ page }) => {
	await stubCatalog(page);
	await page.goto("/series");
	await page.getByRole("link", { name: FILM_SERIES_TITLE }).click();
	await expect(page).toHaveURL(FILM_SERIES_URL);
	await expect(
		page.getByRole("link", { name: FIRST_FILM_LINK }).first(),
	).toBeVisible();
});

test("каталог: франшиза со смешанными элементами", async ({ page }) => {
	await stubCatalog(page);
	await page.goto("/franchises");
	await expect(page.getByRole("heading", { name: "Франшизы" })).toBeVisible();
	await page.getByRole("link", { name: FRANCHISE_TITLE }).click();
	await expect(page.getByRole("link", { name: SERIES_TITLE })).toBeVisible();
	await expect(
		page.getByRole("link", { name: FILM_SERIES_LINK }),
	).toHaveAttribute("href", "/series/9");
	await expect(
		page.getByRole("link", { name: FRANCHISE_MOVIE_LINK }),
	).toHaveAttribute("href", "/video/42");
});

test("каталог: TV-карточки зарегистрированы как фокус-цели", async ({
	page,
}) => {
	await stubCatalog(page);
	await page.goto("/series?tv=1");
	await expect(page.locator('[data-tv-focus-key="series-page"]')).toBeVisible();
	await expect(
		page.locator('[data-tv-focus-key="series-card-7"]'),
	).toBeVisible();
	await expect(
		page.locator('[data-tv-focus-key="film-series-card-9"]'),
	).toBeVisible();
});

test("каталог: TV переживает холодную загрузку и фокусирует карточку", async ({
	page,
}) => {
	await stubCatalog(page, 300);
	await page.goto("/series?tv=1");
	await expect.poll(() => activeKey(page)).toBe("series-card-7");
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeKey(page)).toBe("film-series-card-9");
	await page.keyboard.press("Enter");
	await expect(page).toHaveURL(SERIES_DETAIL_URL);
});

test("каталог: TV холодная детальная сериала", async ({ page }) => {
	await stubCatalog(page);
	await page.unroute("**/api/works/7");
	await page.route("**/api/works/7", async (route) => {
		await new Promise((resolve) => setTimeout(resolve, 300));
		await route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ ...series, seasons: [season] }),
		});
	});
	await page.goto("/series/7?tv=1");
	await expect.poll(() => activeKey(page)).toBe("episode-21");
});

test("каталог: TV холодная детальная франшизы", async ({ page }) => {
	await stubCatalog(page);
	await page.unroute("**/api/franchises/3");
	await page.route("**/api/franchises/3", async (route) => {
		await new Promise((resolve) => setTimeout(resolve, 300));
		await route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(franchiseDetail),
		});
	});
	await page.goto("/franchises/3?tv=1");
	await expect.poll(() => activeKey(page)).toBe("franchise-entry-1");
});

test("видео: сериалы и франшизы — вкладки одного раздела", async ({ page }) => {
	await stubCatalog(page);
	await page.route("**/api/media?*", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ items: [], total: 0, limit: 24, offset: 0 }),
		}),
	);
	await page.goto("/video");
	await expect(page.getByRole("link", { name: "Сериалы" })).toHaveCount(0);
	await page.getByRole("tab", { name: "Сериалы" }).click();
	await expect(
		page.getByRole("heading", { name: "Сериалы", level: 2 }),
	).toBeVisible();
	await page.getByRole("tab", { name: "Франшизы" }).click();
	await expect(page.getByRole("link", { name: FRANCHISE_TITLE })).toBeVisible();
});

test("видео: TV Down с вкладки сериалов ведёт в карточки", async ({ page }) => {
	await stubCatalog(page);
	await page.goto("/video?tv=1");
	await expect.poll(() => activeKey(page)).toBe("video-tab-movies");
	await page.keyboard.press("ArrowRight");
	await expect.poll(() => activeKey(page)).toBe("video-tab-series");
	await page.keyboard.press("Enter");
	await expect(
		page.getByRole("heading", { name: "Сериалы", level: 2 }),
	).toBeVisible();
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeKey(page)).toBe("series-card-7");
});

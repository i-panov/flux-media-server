import { expect, test } from "@playwright/test";

const CODE_PATTERN = /^\d{6}$/;
const SERIES_LINK = /Реальный сериал/;
const SEASON_HEADING = "Сезон 1";
const PILOT_LINK = /Пилот/;
const FRANCHISE_LINK = /Реальная франшиза/;
const FILM_SERIES_LINK = /Реальная серия фильмов/;
const STANDALONE_LINK = /Отдельный фильм/;
const FILM_LINK = /Реальный фильм/;
const SERIES_URL = /\/series\/9002$/;

test("реальный каталог: сериал, film_series и франшиза", async ({ page }) => {
	const email = "catalog-e2e@example.com";
	const codeResponse = await page.request.post("/api/auth/request-code", {
		data: { email },
	});
	expect(codeResponse.ok()).toBeTruthy();
	const { code } = (await codeResponse.json()) as { code: string };
	expect(code).toMatch(CODE_PATTERN);
	const verify = await page.request.post("/api/auth/verify-code", {
		data: { email, code },
	});
	expect(verify.ok()).toBeTruthy();

	await page.goto("/series");
	await expect(
		page.getByRole("heading", { name: "Сериалы и фильмы" }),
	).toBeVisible();
	await page.getByRole("link", { name: SERIES_LINK }).click();
	await expect(
		page.getByRole("heading", { name: SEASON_HEADING }),
	).toBeVisible();
	await expect(page.getByRole("link", { name: PILOT_LINK })).toBeVisible();

	await page.goto("/franchises");
	await expect(page.getByRole("heading", { name: "Франшизы" })).toBeVisible();
	await page.getByRole("link", { name: FRANCHISE_LINK }).click();
	await expect(page.getByRole("link", { name: SERIES_LINK })).toBeVisible();
	await expect(
		page.getByRole("link", { name: FILM_SERIES_LINK }),
	).toBeVisible();
	await expect(page.getByRole("link", { name: STANDALONE_LINK })).toBeVisible();
	await page.getByRole("link", { name: FILM_SERIES_LINK }).click();
	await expect(page).toHaveURL(SERIES_URL);
	await expect(page.getByRole("link", { name: FILM_LINK })).toBeVisible();
});

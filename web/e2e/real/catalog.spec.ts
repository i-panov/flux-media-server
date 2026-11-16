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
const ADMIN_SERIES_LINK = /E2E админ-сериал/;
const ADMIN_EPISODE_LINK = /E2E эпизод/;
const VIDEO_LIST_URL = /\/video$/;
const ADMIN_SEASON_TWO = /Сезон 2/;

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

test("реальный админ: создать сериал, сезон, эпизод, reorder, удалить", async ({
	page,
}) => {
	const email = "catalog-admin@example.com";
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
	await page.getByRole("button", { name: "Добавить", exact: true }).click();
	await page.getByLabel("Название").fill("E2E админ-сериал");
	await page.getByRole("button", { name: "Создать" }).click();
	await expect(
		page.getByRole("link", { name: ADMIN_SERIES_LINK }),
	).toBeVisible();

	const worksResponse = await page.request.get("/api/works?kind=series");
	const works = (await worksResponse.json()) as Array<{
		id: number;
		title: string;
	}>;
	const work = works.find((row) => row.title === "E2E админ-сериал");
	expect(work).toBeTruthy();
	if (!work) return;

	const seasonResponse = await page.request.post(
		`/api/works/${work.id}/seasons`,
		{
			data: { season_number: 2, title: "Сезон 2" },
		},
	);
	expect(seasonResponse.ok()).toBeTruthy();
	const season2 = (await seasonResponse.json()) as { id: number };

	const detailResponse = await page.request.get(`/api/works/${work.id}`);
	const detail = (await detailResponse.json()) as {
		seasons: Array<{ id: number }>;
	};
	const season1 = detail.seasons.find((season) => season.id !== season2.id);
	expect(season1).toBeTruthy();
	if (!season1) return;

	const episodeResponse = await page.request.post(
		`/api/seasons/${season2.id}/items`,
		{ data: { media_id: 9004, episode_number: 1 } },
	);
	expect(episodeResponse.ok()).toBeTruthy();
	const orderResponse = await page.request.put(
		`/api/works/${work.id}/seasons/order`,
		{ data: { season_ids: [season2.id, season1.id] } },
	);
	expect(orderResponse.ok()).toBeTruthy();

	const reorderedResponse = await page.request.get(`/api/works/${work.id}`);
	const reordered = (await reorderedResponse.json()) as {
		seasons: Array<{ id: number; items: Array<{ media_id: number }> }>;
	};
	expect(reordered.seasons[0]?.id).toBe(season2.id);
	expect(reordered.seasons[0]?.items[0]?.media_id).toBe(9004);

	await page.reload();
	await page.getByRole("link", { name: ADMIN_SERIES_LINK }).click();
	await expect(page.getByRole("heading", { name: "Сезон 2" })).toBeVisible();
	await expect(
		page.getByRole("link", { name: ADMIN_EPISODE_LINK }).first(),
	).toBeVisible();
	await expect
		.poll(async () =>
			(await page.getByRole("heading", { level: 2 }).allTextContents()).filter(
				(text) => text.startsWith("Сезон"),
			),
		)
		.toEqual(["Сезон 2", "Сезон 1"]);

	const tagResponse = await page.request.post("/api/tags", {
		data: { group: "format", slug: "e2e-film", name: "E2E фильм" },
	});
	expect(tagResponse.ok()).toBeTruthy();
	const tag = (await tagResponse.json()) as { id: number };
	const setTags = await page.request.put("/api/media/9006/tags", {
		data: { tag_ids: [tag.id] },
	});
	expect(setTags.ok()).toBeTruthy();
	const mediaTags = await page.request.get("/api/media/9006/tags");
	expect(((await mediaTags.json()) as unknown[]).length).toBe(1);

	await page.goto("/video/9006");
	await page.getByRole("button", { name: "В каталог" }).click();
	await page.getByText("E2E админ-сериал", { exact: true }).click();
	await page.getByRole("combobox").last().click();
	await page.getByRole("option", { name: "Сезон 2" }).click();
	await page.getByRole("button", { name: "Добавить", exact: true }).click();
	await expect
		.poll(async () => {
			const response = await page.request.get(
				"/api/media/9006/catalog-context",
			);
			return ((await response.json()) as { season_number: number })
				.season_number;
		})
		.toBe(2);
	await page.reload();
	await expect(
		page.getByText(ADMIN_SEASON_TWO, { exact: false }),
	).toBeVisible();
	await page.goto(`/series/${work.id}`);

	page.once("dialog", (dialog) => void dialog.accept());
	await page.getByRole("button", { name: "Удалить", exact: true }).click();
	await expect(page).toHaveURL(VIDEO_LIST_URL);
	await expect(page.getByRole("link", { name: ADMIN_SERIES_LINK })).toHaveCount(
		0,
	);
	const deletedResponse = await page.request.get(`/api/works/${work.id}`);
	expect(deletedResponse.status()).toBe(404);
});

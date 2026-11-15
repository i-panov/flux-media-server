import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const SERIES_LIST_URL = /\/series$/;
const NEW_SERIES_LINK = /Новый сериал/;

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

test("каталог: админ создаёт сериал", async ({ page }) => {
	await stubAdmin(page);
	let created = false;
	const work = {
		id: 10,
		kind: "series",
		title: "Новый сериал",
		description: "",
		cover_url: "",
		year: 2026,
		seasons: [
			{
				id: 20,
				work_id: 10,
				season_number: 1,
				title: "",
				position: 0,
				items: [],
			},
		],
	};
	await page.route(
		(url) => url.pathname === "/api/works",
		(route) => {
			if (route.request().method() === "POST") {
				created = true;
				return route.fulfill({
					status: 201,
					contentType: "application/json",
					body: JSON.stringify(work),
				});
			}
			const kind = new URL(route.request().url()).searchParams.get("kind");
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(created && kind === "series" ? [work] : []),
			});
		},
	);

	await page.goto("/series");
	await page.getByRole("button", { name: "Добавить" }).click();
	await page.getByLabel("Название").fill("Новый сериал");
	const requestPromise = page.waitForRequest(
		(request) =>
			request.url().endsWith("/api/works") && request.method() === "POST",
	);
	await page.getByRole("button", { name: "Создать" }).click();
	const request = await requestPromise;
	expect(request.postDataJSON()).toMatchObject({
		kind: "series",
		title: "Новый сериал",
	});
	await expect(page.getByRole("dialog")).toBeHidden();
	await expect(page.getByRole("link", { name: NEW_SERIES_LINK })).toBeVisible();
});

test("каталог: админ удаляет сериал с подтверждением", async ({ page }) => {
	await stubAdmin(page);
	let deleted = false;
	await page.route("**/api/works/7", (route) => {
		if (route.request().method() === "DELETE") {
			deleted = true;
			return route.fulfill({ status: 204 });
		}
		return route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 7,
				kind: "series",
				title: "Тестовый сериал",
				description: "",
				cover_url: "",
				year: 2026,
				seasons: [],
				items: [],
			}),
		});
	});
	await page.route(
		(url) => url.pathname === "/api/works",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: "[]",
			}),
	);
	let dialogType = "";
	page.once("dialog", (dialog) => {
		dialogType = dialog.type();
		void dialog.accept();
	});
	await page.goto("/series/7");
	await page.getByRole("button", { name: "Удалить" }).click();
	expect(dialogType).toBe("confirm");
	await expect.poll(() => deleted).toBe(true);
	await expect(page).toHaveURL(SERIES_LIST_URL);
});

test("каталог: админ меняет порядок сезонов с клавиатуры", async ({ page }) => {
	await stubAdmin(page);
	const seasons = [
		{
			id: 20,
			work_id: 7,
			season_number: 1,
			title: "Сезон 1",
			position: 0,
			items: [],
		},
		{
			id: 21,
			work_id: 7,
			season_number: 2,
			title: "Сезон 2",
			position: 1,
			items: [],
		},
	];
	await page.route("**/api/works/7", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 7,
				kind: "series",
				title: "Тестовый сериал",
				description: "",
				cover_url: "",
				year: 2026,
				seasons,
				items: [],
			}),
		}),
	);
	let order: unknown = null;
	let active = seasons;
	await page.route("**/api/works/7/seasons/order", (route) => {
		order = route.request().postDataJSON();
		active = [...seasons].reverse();
		return route.fulfill({ status: 204 });
	});
	await page.route("**/api/works/7", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				...{
					id: 7,
					kind: "series",
					title: "Тестовый сериал",
					description: "",
					cover_url: "",
					year: 2026,
					items: [],
				},
				seasons: active,
			}),
		}),
	);
	await page.goto("/series/7");
	const handles = page.getByRole("button", { name: "Перетащить" });
	await expect(handles).toHaveCount(2);
	await handles.first().focus();
	await page.keyboard.press("Space");
	await page.waitForTimeout(200);
	await page.keyboard.press("ArrowDown");
	await page.waitForTimeout(200);
	await page.keyboard.press("Space");
	await expect
		.poll(() => order, { timeout: 10_000 })
		.toEqual({ season_ids: [21, 20] });
	const headings = page.getByRole("heading", { level: 2 });
	await expect
		.poll(async () => (await headings.allTextContents()).slice(0, 2))
		.toEqual(["Сезон 2", "Сезон 1"]);
});

test("каталог: не-админ не видит управление", async ({ page }) => {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 2,
				email: "user@example.com",
				is_admin: false,
			}),
		}),
	);
	await stubEmptyLibraryMeta(page);
	await page.route("**/api/works/7", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 7,
				kind: "series",
				title: "Сериал",
				description: "",
				cover_url: "",
				year: 2026,
				seasons: [],
				items: [],
			}),
		}),
	);
	await page.goto("/series/7");
	await expect(page.getByRole("heading", { name: "Сериал" })).toBeVisible();
	await expect(page.getByText("Управление каталогом")).toHaveCount(0);
	await expect(page.getByRole("button", { name: "Удалить" })).toHaveCount(0);
});

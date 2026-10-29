import { expect, type Page, test } from "@playwright/test";

const healthBody = JSON.stringify({ status: "ok", version: "1.0.8" });
const testUser = {
	id: 1,
	email: "user@example.com",
	is_admin: false,
};
const userBody = JSON.stringify(testUser);
const unauthorizedBody = JSON.stringify({ error: "Unauthorized" });

async function stubHealth(page: Page) {
	await page.route("**/api/health", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: healthBody,
		}),
	);
}

async function stubRefreshUnauthorized(page: Page) {
	await page.route("**/api/auth/refresh", (route) =>
		route.fulfill({
			status: 401,
			contentType: "application/json",
			body: unauthorizedBody,
		}),
	);
}

function stubMe(page: Page, authed: () => boolean) {
	return page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: authed() ? 200 : 401,
			contentType: "application/json",
			body: authed() ? userBody : unauthorizedBody,
		}),
	);
}

test("гость перенаправляется на страницу входа", async ({ page }) => {
	await stubMe(page, () => false);
	await stubRefreshUnauthorized(page);
	await stubHealth(page);

	await page.goto("/");

	await expect(
		page.getByRole("heading", { level: 1, name: "Вход" }),
	).toBeVisible();
	await expect(page.getByLabel("Электронная почта")).toBeVisible();
});

test("карточка входа центрирована по вьюпорту", async ({ page }) => {
	await stubMe(page, () => false);
	await stubRefreshUnauthorized(page);
	await stubHealth(page);

	await page.goto("/login");
	const card = page.getByTestId("login-card");

	const desktopViewport = page.viewportSize();
	if (desktopViewport === null) {
		throw new Error("viewport is not set");
	}
	const desktopBox = await card.boundingBox();
	if (desktopBox === null) {
		throw new Error("login card is not rendered");
	}
	expect(
		Math.abs(desktopBox.x + desktopBox.width / 2 - desktopViewport.width / 2),
	).toBeLessThan(5);

	await page.setViewportSize({ width: 390, height: 844 });
	const mobileBox = await card.boundingBox();
	if (mobileBox === null) {
		throw new Error("login card disappeared after resize");
	}
	expect(Math.abs(mobileBox.x + mobileBox.width / 2 - 390 / 2)).toBeLessThan(5);
});

test("вход по коду и выход", async ({ page }) => {
	let authed = false;
	await stubMe(page, () => authed);
	await stubRefreshUnauthorized(page);
	await stubHealth(page);
	await page.route("**/api/auth/request-code", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ message: "Code sent", code: "123456" }),
		}),
	);
	await page.route("**/api/auth/verify-code", (route) => {
		authed = true;
		return route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				token: "access",
				refresh_token: "refresh",
				user: testUser,
			}),
		});
	});
	await page.route("**/api/auth/logout", (route) => {
		authed = false;
		return route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ message: "ok" }),
		});
	});

	await page.goto("/");

	await page.getByLabel("Электронная почта").fill("user@example.com");
	await page.getByRole("button", { name: "Получить код" }).click();

	await expect(
		page.getByText("Код отправлен на user@example.com"),
	).toBeVisible();
	await expect(page.getByText("123456")).toBeVisible();

	await page.getByLabel("Код из письма").fill("123456");
	await page.getByRole("button", { name: "Войти" }).click();

	await expect(
		page.getByRole("heading", { level: 1, name: "Flux" }),
	).toBeVisible();
	await expect(page.getByText("user@example.com")).toBeVisible();

	await page.getByRole("button", { name: "Выйти" }).click();

	await expect(
		page.getByRole("heading", { level: 1, name: "Вход" }),
	).toBeVisible();
});

test("неверный код показывает ошибку", async ({ page }) => {
	await stubMe(page, () => false);
	await stubRefreshUnauthorized(page);
	await page.route("**/api/auth/request-code", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ message: "Code sent" }),
		}),
	);
	await page.route("**/api/auth/verify-code", (route) =>
		route.fulfill({
			status: 401,
			contentType: "application/json",
			body: JSON.stringify({ error: "Invalid or expired code" }),
		}),
	);

	await page.goto("/login");

	await page.getByLabel("Электронная почта").fill("user@example.com");
	await page.getByRole("button", { name: "Получить код" }).click();
	await page.getByLabel("Код из письма").fill("000000");
	await page.getByRole("button", { name: "Войти" }).click();

	await expect(page.getByText("Неверный или просроченный код")).toBeVisible();
});

test("недоступный сервер показывает экран ошибки, а не логин", async ({
	page,
}) => {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 500,
			contentType: "application/json",
			body: JSON.stringify({ error: "boom" }),
		}),
	);

	await page.goto("/");

	await expect(page.getByText("Что-то пошло не так")).toBeVisible();
	await expect(
		page.getByRole("button", { name: "Попробовать снова" }),
	).toBeVisible();
	await expect(
		page.getByRole("heading", { level: 1, name: "Вход" }),
	).toBeHidden();
});

test("повтор после ошибки перепроверяет сессию", async ({ page }) => {
	let meCalls = 0;
	await page.route("**/api/auth/me", (route) => {
		meCalls += 1;
		const recovered = meCalls > 1;
		return route.fulfill({
			status: recovered ? 200 : 500,
			contentType: "application/json",
			body: recovered
				? JSON.stringify({
						id: 1,
						email: "user@example.com",
						is_admin: false,
					})
				: JSON.stringify({ error: "boom" }),
		});
	});
	await stubHealth(page);

	await page.goto("/");

	await expect(page.getByText("Что-то пошло не так")).toBeVisible();
	expect(meCalls).toBeGreaterThanOrEqual(1);

	await page.getByRole("button", { name: "Попробовать снова" }).click();

	// Повтор ушёл в сеть и после восстановления привёл на главную.
	await expect(
		page.getByRole("heading", { level: 1, name: "Flux" }),
	).toBeVisible();
	expect(meCalls).toBeGreaterThanOrEqual(2);
});

test("выход при недоступном сервере показывает ошибку", async ({ page }) => {
	await stubMe(page, () => true);
	await stubHealth(page);
	await page.route("**/api/auth/logout", (route) =>
		route.fulfill({
			status: 500,
			contentType: "application/json",
			body: JSON.stringify({ error: "boom" }),
		}),
	);

	await page.goto("/");

	await expect(
		page.getByRole("heading", { level: 1, name: "Flux" }),
	).toBeVisible();
	await page.getByRole("button", { name: "Выйти" }).click();

	await expect(page.getByText("Не удалось выйти из аккаунта")).toBeVisible();
	await expect(page.getByText("user@example.com")).toBeVisible();
});

test("выход с истёкшей сессией ведёт на логин", async ({ page }) => {
	await stubMe(page, () => true);
	await stubHealth(page);
	await stubRefreshUnauthorized(page);
	await page.route("**/api/auth/logout", (route) =>
		route.fulfill({
			status: 401,
			contentType: "application/json",
			body: unauthorizedBody,
		}),
	);

	await page.goto("/");

	await expect(
		page.getByRole("heading", { level: 1, name: "Flux" }),
	).toBeVisible();
	await page.getByRole("button", { name: "Выйти" }).click();

	await expect(
		page.getByRole("heading", { level: 1, name: "Вход" }),
	).toBeVisible();
});

import { expect, type Page, test } from "@playwright/test";

const TIZEN_UA =
	"Mozilla/5.0 (SMART-TV; Linux; Tizen 6.5) AppleWebKit/537.36 (KHTML, like Gecko) 76.0.3809.146/6.5 TV Safari/537.36";

async function stubGuest(page: Page) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 401,
			contentType: "application/json",
			body: JSON.stringify({ error: "Unauthorized" }),
		}),
	);
	await page.route("**/api/auth/refresh", (route) =>
		route.fulfill({
			status: 401,
			contentType: "application/json",
			body: JSON.stringify({ error: "Unauthorized" }),
		}),
	);
	await page.route("**/api/health", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ status: "ok", version: "9.9.9" }),
		}),
	);
}

function activeFocusKey(page: Page): Promise<string> {
	return page.evaluate(
		() => document.activeElement?.getAttribute("data-tv-focus-key") ?? "",
	);
}

async function pressUntilFocusKey(
	page: Page,
	key: string,
	matches: (value: string) => boolean,
	attempts = 8,
): Promise<string> {
	for (let index = 0; index < attempts; index += 1) {
		const current = await activeFocusKey(page);
		if (matches(current)) {
			return current;
		}
		await page.keyboard.press(key);
		await page.waitForTimeout(60);
	}
	const current = await activeFocusKey(page);
	if (matches(current)) {
		return current;
	}
	throw new Error(`фокус не дошёл до цели, последний ключ: ${current}`);
}

test.describe("ТВ-автодетект Tizen", () => {
	test.use({ userAgent: TIZEN_UA });

	test("логин: фокус на email, кнопки и переход к коду", async ({ page }) => {
		await stubGuest(page);
		await page.route("**/api/auth/request-code", (route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ message: "Code sent", code: "123456" }),
			}),
		);

		await page.goto("/login");
		// Автодетект по UA включает ТВ без ?tv=1.
		await expect
			.poll(() =>
				page.evaluate(() =>
					document.getElementById("root")?.classList.contains("tv-mode"),
				),
			)
			.toBe(true);
		await expect.poll(() => activeFocusKey(page)).toBe("login-email");

		// Кнопка отправки — тоже spatial-цель, не только поле.
		await pressUntilFocusKey(
			page,
			"ArrowDown",
			(key) => key === "login-submit",
		);
		await pressUntilFocusKey(page, "ArrowUp", (key) => key === "login-email");

		await page.keyboard.type("user@example.com");
		await page.keyboard.press("Enter");
		await expect(
			page.getByText("Код отправлен на user@example.com"),
		).toBeVisible();
		await expect.poll(() => activeFocusKey(page)).toBe("login-code");
	});
});

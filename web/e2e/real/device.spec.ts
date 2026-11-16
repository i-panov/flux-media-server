import { expect, test } from "@playwright/test";

const ADMIN_EMAIL = "catalog-admin@example.com";
const DEVICE_CODE_PATTERN = /^\d{6}$/;
const ACTIVATE_URL = /\/activate$/;

async function login(page: import("@playwright/test").Page) {
	const request = await page.request.post("/api/auth/request-code", {
		data: { email: ADMIN_EMAIL },
	});
	expect(request.ok()).toBeTruthy();
	const { code } = (await request.json()) as { code: string };
	const verify = await page.request.post("/api/auth/verify-code", {
		data: { email: ADMIN_EMAIL, code },
	});
	expect(verify.ok()).toBeTruthy();
}

test("устройство: код с TV подтверждается во втором браузере", async ({
	browser,
	baseURL,
}) => {
	const deviceContext = await browser.newContext({ baseURL });
	const userContext = await browser.newContext({ baseURL });
	const devicePage = await deviceContext.newPage();
	const userPage = await userContext.newPage();

	const created = await devicePage.request.post("/api/auth/device/code", {
		data: { device_name: "E2E Television", platform: "tv" },
	});
	expect(created.ok()).toBeTruthy();
	const { device_code, user_code } = (await created.json()) as {
		device_code: string;
		user_code: string;
	};
	expect(user_code).toMatch(DEVICE_CODE_PATTERN);

	await login(userPage);
	await userPage.goto("/settings");
	await userPage.getByRole("link", { name: "Подтвердить устройство" }).click();
	await expect(userPage).toHaveURL(ACTIVATE_URL);
	const wrong = user_code === "000000" ? "000001" : "000000";
	await userPage.getByLabel("Код устройства").fill(wrong);
	await userPage.getByRole("button", { name: "Проверить код" }).click();
	await expect(
		userPage.getByText("Код не найден или уже использован."),
	).toBeVisible();

	const formatted = `${user_code.slice(0, 3)} ${user_code.slice(3)}`;
	await userPage.getByLabel("Код устройства").fill(formatted);
	await userPage.getByRole("button", { name: "Проверить код" }).click();
	await expect(userPage.getByText("E2E Television")).toBeVisible();
	await userPage.getByRole("button", { name: "Подтвердить вход" }).click();
	await expect(
		userPage.getByText("Устройство подтверждено. Вернитесь на телевизор."),
	).toBeVisible();

	const token = await devicePage.request.post("/api/auth/device/token", {
		data: { device_code },
	});
	expect(token.ok()).toBeTruthy();
	const tokenBody = (await token.json()) as { status?: string };
	expect(tokenBody.status).toBe("ok");

	const me = await devicePage.request.get("/api/auth/me");
	expect(me.ok()).toBeTruthy();
	const meBody = (await me.json()) as { email: string };
	expect(meBody.email).toBe(ADMIN_EMAIL);

	await deviceContext.close();
	await userContext.close();
});

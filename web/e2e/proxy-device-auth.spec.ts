import { expect, test } from "@playwright/test";

const VIDEO_URL = /\/video$/;
const SIX_DIGITS = /^\d{6}$/;

// Два независимых браузерных контекста: один уже вошёл, второй
// подтверждает вход по коду. Это ровно сценарий TV + телефон/ПК.
test("вход по device-code из второго браузера", async ({ browser }) => {
	const owner = await browser.newContext();
	const tv = await browser.newContext();
	const ownerPage = await owner.newPage();
	const tvPage = await tv.newPage();

	try {
		await ownerPage.goto("/login");
		await ownerPage.getByLabel("Электронная почта").fill("user@example.com");
		const codeResponse = ownerPage.waitForResponse((response) =>
			response.url().includes("/api/auth/request-code"),
		);
		await ownerPage.getByRole("button", { name: "Получить код" }).click();
		const debugCode = (await (await codeResponse).json()) as { code?: string };
		const otp = typeof debugCode.code === "string" ? debugCode.code : "123456";
		await ownerPage.getByLabel("Код из письма").fill(otp);
		await ownerPage.getByRole("button", { name: "Войти", exact: true }).click();
		await expect(ownerPage).toHaveURL(VIDEO_URL);

		await tvPage.goto("/login?tv=1");
		await expect(tvPage.getByTestId("device-qr")).toBeVisible();
		const code = await tvPage.getByTestId("device-user-code").textContent();
		expect(code).toMatch(SIX_DIGITS);

		await ownerPage.goto(`/activate#code=${code}`);
		await expect(ownerPage.getByText(/Web TV|Fake TV/)).toBeVisible();
		await ownerPage.getByRole("button", { name: "Подтвердить вход" }).click();
		await expect(ownerPage.getByText("Устройство подтверждено")).toBeVisible();

		await expect(tvPage).toHaveURL(VIDEO_URL, { timeout: 15_000 });
	} finally {
		await owner.close();
		await tv.close();
	}
});

import { expect, test } from "@playwright/test";

const CODE_PATTERN = /^\d{6}$/;
const VIDEO_URL_PATTERN = /\/video\/\d+$/;

test("реальный путь: ссылка → media-loader → Flux → карточка играет", async ({
	page,
}) => {
	const email = "e2e@example.com";
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

	await page.goto("/upload?type=video");
	await page
		.getByTestId("upload-link-url")
		.fill("http://host.docker.internal:18082/video.mp4");
	await page.getByTestId("upload-link-submit").click();

	await expect(page.getByTestId("upload-link-job")).toBeVisible({
		timeout: 60_000,
	});
	await expect(page.getByTestId("upload-link-job")).toHaveCount(0, {
		timeout: 120_000,
	});

	await page.goto("/video");
	await expect
		.poll(() => page.locator('a[href^="/video/"]').count(), {
			timeout: 120_000,
		})
		.toBeGreaterThan(0);
	await page.locator('a[href^="/video/"]').first().click();
	await expect(page).toHaveURL(VIDEO_URL_PATTERN);
	await expect(page.locator("video")).toBeVisible();

	await expect
		.poll(
			() =>
				page.locator("video").evaluate((element) => {
					const video = element as HTMLVideoElement;
					return video.readyState;
				}),
			{ timeout: 30_000 },
		)
		.toBeGreaterThanOrEqual(2);
	await expect(page.getByText("Не удалось загрузить видео")).toHaveCount(0);
});

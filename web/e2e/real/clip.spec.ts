import { expect, test } from "@playwright/test";

const CODE_PATTERN = /^\d{6}$/;
const EMAIL = "clip@example.com";
const SOURCE_MEDIA_ID = 9007;

test("реальная обрезка: фрагмент создаётся и оригинал не меняется", async ({
	page,
}) => {
	const codeResponse = await page.request.post("/api/auth/request-code", {
		data: { email: EMAIL },
	});
	expect(codeResponse.ok()).toBeTruthy();
	const { code } = (await codeResponse.json()) as { code: string };
	expect(code).toMatch(CODE_PATTERN);
	const verify = await page.request.post("/api/auth/verify-code", {
		data: { email: EMAIL, code },
	});
	expect(verify.ok()).toBeTruthy();

	const original = await page.request.get(`/api/media/${SOURCE_MEDIA_ID}`);
	expect(original.ok()).toBeTruthy();
	const originalMedia = (await original.json()) as {
		id: number;
		duration: number;
		title: string;
	};

	const created = await page.request.post(
		`/api/media/${SOURCE_MEDIA_ID}/clip`,
		{
			data: { start: 0.05, end: 1.15, title: "E2E фрагмент" },
		},
	);
	expect(created.status()).toBe(202);
	const task = (await created.json()) as { id: number };

	let outputMediaID = 0;
	await expect
		.poll(
			async () => {
				const status = await page.request.get(`/api/clips/${task.id}`);
				const body = (await status.json()) as {
					status: string;
					output_media_id?: number;
					error?: string;
				};
				if (body.status === "error") {
					throw new Error(body.error ?? "clip failed");
				}
				outputMediaID = body.output_media_id ?? 0;
				return body.status;
			},
			{ timeout: 180_000 },
		)
		.toBe("done");

	const output = await page.request.get(`/api/media/${outputMediaID}`);
	expect(output.ok()).toBeTruthy();
	const clipped = (await output.json()) as {
		id: number;
		duration: number;
		source_media_id?: number;
		title: string;
	};
	expect(clipped.id).not.toBe(SOURCE_MEDIA_ID);
	expect(clipped.source_media_id).toBe(SOURCE_MEDIA_ID);
	expect(clipped.title).toBe("E2E фрагмент");
	expect(clipped.duration).toBeGreaterThanOrEqual(1);
	expect(clipped.duration).toBeLessThanOrEqual(2);

	const originalAfter = await page.request.get(`/api/media/${SOURCE_MEDIA_ID}`);
	expect(originalAfter.ok()).toBeTruthy();
	const originalAgain = (await originalAfter.json()) as {
		duration: number;
		title: string;
	};
	expect(originalAgain.duration).toBe(originalMedia.duration);
	expect(originalAgain.title).toBe(originalMedia.title);
});

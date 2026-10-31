import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";
import { stubAuthedSession, stubVideoApi, videoItem } from "./video-fixtures";

const VIDEO_LIST_PATTERN = /\/video(\?|$)/;
const PLAYER_PATTERN = /\/player(\?|$)/;
const AUDIO_LIST_PATTERN = /\/audio(\?|$)/;
const VIDEO_DETAIL_ID_PATTERN = /\/video\/2(\?|$)/;
const PROGRESS_ID_PATTERN = /^\/api\/progress\/\d+$/;
const LYRICS_PATTERN = /^\/api\/media\/\d+\/lyrics$/;
const STREAM_PATTERN = /^\/api\/media\/\d+\/stream$/;

function audioItem(id: number, title: string) {
	return {
		id,
		title,
		filename: `track-${id}.wav`,
		year: 2024,
		description: "",
		type: "audio",
		artists: [{ id: 1, name: "Исполнитель" }],
		album: "Альбом",
		genre: "Жанр",
		duration: 120,
		width: 0,
		height: 0,
		file_size: 100,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: `/api/media/${id}/cover`,
		view_count: 1,
		created_at: "2026-01-01T00:00:00Z",
	};
}

function silentWav(seconds = 60): Buffer {
	const sampleRate = 8000;
	const dataSize = sampleRate * seconds * 2;
	const buffer = Buffer.alloc(44 + dataSize);
	buffer.write("RIFF", 0);
	buffer.writeUInt32LE(36 + dataSize, 4);
	buffer.write("WAVE", 8);
	buffer.write("fmt ", 12);
	buffer.writeUInt32LE(16, 16);
	buffer.writeUInt16LE(1, 20);
	buffer.writeUInt16LE(1, 22);
	buffer.writeUInt32LE(sampleRate, 24);
	buffer.writeUInt32LE(sampleRate * 2, 28);
	buffer.writeUInt16LE(2, 32);
	buffer.writeUInt16LE(16, 34);
	buffer.write("data", 36);
	buffer.writeUInt32LE(dataSize, 40);
	return buffer;
}

async function stubVideoDetail(page: Page, id: number, title: string) {
	await page.route(`**/api/media/${id}`, (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(videoItem(id, title)),
		}),
	);
	await page.route(`**/api/media/${id}/subs`, (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: "[]",
		}),
	);
	await page.route(`**/api/media/${id}/stream`, (route) =>
		route.fulfill({
			status: 200,
			contentType: "video/mp4",
			body: "",
		}),
	);
}

async function stubAudioForTV(page: Page) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 1,
				email: "user@example.com",
				is_admin: false,
			}),
		}),
	);
	await stubEmptyLibraryMeta(page);
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [audioItem(1, "Первый трек"), audioItem(2, "Второй трек")],
					total: 2,
					limit: 24,
					offset: 0,
				}),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/progress",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 20, offset: 0 }),
			}),
	);
	await page.route(
		(url) => PROGRESS_ID_PATTERN.test(url.pathname),
		(route) =>
			route.fulfill({
				status: 404,
				contentType: "application/json",
				body: JSON.stringify({ error: "not found" }),
			}),
	);
	await page.route(
		(url) => LYRICS_PATTERN.test(url.pathname),
		(route) =>
			route.fulfill({
				status: 404,
				contentType: "application/json",
				body: JSON.stringify({ error: "not found" }),
			}),
	);
	await page.route(
		(url) => STREAM_PATTERN.test(url.pathname),
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "audio/wav",
				body: silentWav(),
			}),
	);
	await page.route(
		(url) => url.pathname.endsWith("/cover"),
		(route) =>
			route.fulfill({
				status: 404,
				contentType: "application/json",
				body: JSON.stringify({ error: "no cover" }),
			}),
	);
}

function activeElementText(page: Page): Promise<string> {
	return page.evaluate(() => document.activeElement?.textContent ?? "");
}

function activeElementTag(page: Page): Promise<string> {
	return page.evaluate(() => document.activeElement?.tagName ?? "");
}

test("ТВ: стрелки ходят между карточками, Enter открывает, Back возвращается", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");

	await page.goto("/video?tv=1");
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();
	await expect(
		page.evaluate(() =>
			document.getElementById("root")?.classList.contains("tv-mode"),
		),
	).resolves.toBe(true);

	// Смена роута ставит фокус на первую карточку.
	await expect.poll(() => activeElementText(page)).toContain("Первый фильм");

	await page.keyboard.press("ArrowRight");
	// Фокус ушёл на соседнюю карточку.
	await expect.poll(() => activeElementText(page)).toContain("Второй фильм");

	await page.keyboard.press("Enter");
	await expect(page).toHaveURL(VIDEO_DETAIL_ID_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Второй фильм" }),
	).toBeVisible();

	// Back пульта — назад к списку.
	await page.keyboard.press("Escape");
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();
});

test("ТВ: плеер с пульта — стрелки сикают и меняют громкость", async ({
	page,
}) => {
	await stubAudioForTV(page);

	await page.goto("/audio?tv=1");
	await page.getByRole("button", { name: "Слушать" }).first().click();
	await expect(page).toHaveURL(PLAYER_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Первый трек" }),
	).toBeVisible();

	const currentTime = () =>
		page.evaluate(() => document.querySelector("audio")?.currentTime ?? -1);
	const volume = () =>
		page.evaluate(() => document.querySelector("audio")?.volume ?? -1);

	const started = await currentTime();
	await page.keyboard.press("ArrowRight");
	// Пульт сикает на 10 секунд (запас на дрейф playing-трека).
	await expect
		.poll(() => currentTime(), { timeout: 10_000 })
		.toBeGreaterThan(started + 5);

	const afterForward = await currentTime();
	await page.keyboard.press("ArrowLeft");
	await expect
		.poll(() => currentTime(), { timeout: 10_000 })
		.toBeLessThan(afterForward - 5);

	const startVolume = await volume();
	await page.keyboard.press("ArrowDown");
	await expect
		.poll(() => volume(), { timeout: 10_000 })
		.toBeLessThan(startVolume);

	// Media-клавиша пульта — следующий трек.
	await page.evaluate(() => {
		window.dispatchEvent(
			new KeyboardEvent("keydown", { key: "MediaTrackNext" }),
		);
	});
	await expect(
		page.getByRole("heading", { level: 1, name: "Второй трек" }),
	).toBeVisible();

	// Back пульта — назад к списку аудио.
	await page.keyboard.press("Escape");
	await expect(page).toHaveURL(AUDIO_LIST_PATTERN);
});

test("обычный режим: стрелки фокус не двигают", async ({ page }) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);

	await page.goto("/video");
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();
	await expect(
		page.evaluate(() =>
			document.getElementById("root")?.classList.contains("tv-mode"),
		),
	).resolves.toBe(false);

	await page.keyboard.press("ArrowRight");
	expect(await activeElementTag(page)).toBe("BODY");
});

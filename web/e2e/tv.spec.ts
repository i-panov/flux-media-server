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

async function stubVideoDetail(
	page: Page,
	id: number,
	title: string,
	delayMs = 0,
) {
	await page.route(`**/api/media/${id}`, async (route) => {
		if (delayMs > 0) {
			await new Promise((resolve) => setTimeout(resolve, delayMs));
		}
		await route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(videoItem(id, title)),
		});
	});
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

async function stubSettings(page: Page) {
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
		(url) => url.pathname === "/api/health",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ status: "ok", version: "9.9.9" }),
			}),
	);
}

function activeElementText(page: Page): Promise<string> {
	return page.evaluate(() => document.activeElement?.textContent ?? "");
}

function activeElementTag(page: Page): Promise<string> {
	return page.evaluate(() => document.activeElement?.tagName ?? "");
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

test("ТВ: список видео, карточки, детали и Back", async ({ page }) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");

	await page.goto("/video?tv=1");
	// Начальный route-focus ведёт на первую карточку.
	await expect.poll(() => activeElementText(page)).toContain("Первый фильм");

	await page.keyboard.press("ArrowRight");
	await expect.poll(() => activeElementText(page)).toContain("Второй фильм");
	await expect.poll(() => activeFocusKey(page)).toContain("video-card-2-");
	// Ждём не таймаут, а фактическую отметку spatial-фокуса: под
	// параллельной нагрузкой DOM-фокус появляется раньше неё.
	await expect
		.poll(() =>
			page.evaluate(
				() => document.activeElement?.getAttribute("data-focused") === "true",
			),
		)
		.toBe(true);

	await page.keyboard.press("Enter");
	await expect(page).toHaveURL(VIDEO_DETAIL_ID_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Второй фильм" }),
	).toBeVisible();
	// Read-only: добавление в коллекцию и правка скрыты.
	await expect(page.getByRole("button", { name: "В коллекцию" })).toHaveCount(
		0,
	);

	// Back пульта — назад к списку.
	await page.keyboard.press("Escape");
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();
});

test("ТВ: /upload?tv=1 сохраняет режим после redirect и reload", async ({
	page,
}) => {
	await stubAuthedSession(page);

	await page.goto("/upload?tv=1");
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Видео" }),
	).toBeVisible();
	// Guard пишет режим до redirect: без этого reload терял ТВ.
	await expect
		.poll(() =>
			page.evaluate(() => window.localStorage.getItem("flux.tv-mode")),
		)
		.toBe("1");

	await page.reload();
	await expect(
		page.getByRole("heading", { level: 1, name: "Видео" }),
	).toBeVisible();
	await expect
		.poll(() =>
			page.evaluate(() =>
				document.getElementById("root")?.classList.contains("tv-mode"),
			),
		)
		.toBe(true);

	await page.goto("/trash?tv=1");
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
});

test("ТВ: Back закрывает Select и возвращает фокус, история не меняется", async ({
	page,
}) => {
	await stubSettings(page);

	await page.goto("/settings?tv=1");
	// Первая цель страницы — переключатель темы, затем тумблер ТВ,
	// затем Select языка.
	await expect.poll(() => activeFocusKey(page)).toBe("settings-theme");
	await pressUntilFocusKey(
		page,
		"ArrowDown",
		(key) => key === "settings-tv-toggle",
	);
	await pressUntilFocusKey(
		page,
		"ArrowRight",
		(key) => key === "settings-language",
	);

	await page.keyboard.press("Enter");
	await expect(page.getByRole("listbox")).toBeVisible();
	const url = page.url();

	// Пультовый GoBack (Tizen/LG шлют коды, а не Escape).
	await page.evaluate(() => {
		window.dispatchEvent(
			new KeyboardEvent("keydown", { key: "GoBack", bubbles: true }),
		);
	});
	await expect(page.getByRole("listbox")).toBeHidden();
	expect(page.url()).toBe(url);
	// Фокус остался на обёртке Select (spatial-ключ не потерян).
	await expect
		.poll(() =>
			page.evaluate(
				() =>
					document.activeElement?.closest(
						'[data-tv-focus-key="settings-language"]',
					) !== null,
			),
		)
		.toBe(true);
	// Ссылки на корзину в ТВ-настройках нет.
	await expect(page.getByRole("link", { name: "Корзина" })).toHaveCount(0);
});

test("ТВ: тумблер режима выключается и включается с пульта", async ({
	page,
}) => {
	await stubSettings(page);

	await page.goto("/settings?tv=1");
	await expect.poll(() => activeFocusKey(page)).toBe("settings-theme");
	await pressUntilFocusKey(
		page,
		"ArrowDown",
		(key) => key === "settings-tv-toggle",
	);

	const isTV = () =>
		page.evaluate(() =>
			document.getElementById("root")?.classList.contains("tv-mode"),
		);
	const stored = () =>
		page.evaluate(() => window.localStorage.getItem("flux.tv-mode"));

	await page.keyboard.press("Enter");
	await expect.poll(isTV).toBe(false);
	await expect.poll(stored).toBe("0");
	// Устаревший ?tv=1 убран, иначе reload снова включил бы режим.
	await expect.poll(() => page.url()).not.toContain("tv=1");

	// Reload с сохранённым "0" остаётся вне ТВ.
	await page.reload();
	await expect.poll(isTV).toBe(false);
	await expect.poll(stored).toBe("0");

	// Включаем обратно с клавиатуры: фокус на чекбокс, Space — переключение.
	await page.getByLabel("ТВ-режим").focus();
	await page.keyboard.press("Space");
	await expect.poll(isTV).toBe(true);
	await expect.poll(stored).toBe("1");
	// Пространственная навигация после off→on жива: route-focus ведёт на
	// тему, а стрелка уводит на тумблер, а не оставляет пустой реестр.
	await expect.poll(() => activeFocusKey(page)).toBe("settings-theme");
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeFocusKey(page)).toBe("settings-tv-toggle");
});

test("ТВ: детали с задержкой API получают фокус на скелетоне и контенте", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubVideoDetail(page, 2, "Второй фильм", 1200);

	await page.goto("/video/2?tv=1");
	await expect.poll(() => activeFocusKey(page)).toBe("video-detail-loading");

	await expect(
		page.getByRole("heading", { level: 1, name: "Второй фильм" }),
	).toBeVisible();
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-play");
});

test("ТВ: мини-плеер открывает полный аудиоплеер", async ({ page }) => {
	await stubAudioForTV(page);

	await page.goto("/audio?tv=1");
	await expect.poll(() => activeFocusKey(page)).toContain("audio-row-1");
	await page.keyboard.press("Enter");
	await expect(page.locator(".audio-mini-player")).toBeVisible();
	await pressUntilFocusKey(
		page,
		"ArrowDown",
		(key) => key === "audio-mini-open",
	);
	await page.keyboard.press("Enter");
	await expect(page).toHaveURL(PLAYER_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Первый трек" }),
	).toBeVisible();

	// Полный плеер открылся с мини-плеера; seek/volume с пульта
	// покрыты unit-тестами tvPlayerRemote.
	await expect(page.getByTestId("player-play")).toBeVisible();
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

import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const AUDIO_DETAIL_ID_PATTERN = /\/audio\/1(\?|$)/;
const FAVORITE_LABEL_PATTERN = /избранное/;

function artistAudioItem(id: number, title: string) {
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

async function stubArtistPage(page: Page) {
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
	// Больше одной страницы: проверяем фокус на «Показать ещё».
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [
						artistAudioItem(1, "Первый трек"),
						artistAudioItem(2, "Второй трек"),
					],
					total: 100,
					limit: 24,
					offset: 0,
				}),
			}),
	);
	await page.route("**/api/media/1", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(artistAudioItem(1, "Первый трек")),
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
	await page.route(
		(url) => url.pathname === "/api/artists",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [
						{
							id: 1,
							name: "Исполнитель",
							has_cover: false,
							updated_at: "2026-01-01T00:00:00Z",
						},
					],
				}),
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

test("ТВ: страница артиста read-only, треки и load-more с пульта", async ({
	page,
}) => {
	await stubArtistPage(page);

	await page.goto("/artists/1?tv=1");
	await expect(
		page.getByRole("heading", { level: 1, name: "Исполнитель" }),
	).toBeVisible();
	await expect(page.getByText("Первый трек")).toBeVisible();

	// Read-only даже для админа: write-кнопок нет.
	await expect(page.getByRole("button", { name: "Переименовать" })).toHaveCount(
		0,
	);
	await expect(page.getByRole("button", { name: "Изменить" })).toHaveCount(0);
	await expect(
		page.getByRole("button", { name: "Заменить обложку" }),
	).toHaveCount(0);
	// Избранное осталось и зарегистрировано как spatial-цель.
	await expect(
		page.getByRole("button", { name: FAVORITE_LABEL_PATTERN }),
	).toBeVisible();
	await expect(
		page.locator('[data-tv-focus-key="artist-favorite"]'),
	).toHaveCount(1);

	// Back — первая цель; треки и load-more достижимы стрелками.
	await expect.poll(() => activeFocusKey(page)).toBe("artist-back");
	await pressUntilFocusKey(page, "ArrowDown", (key) =>
		key.startsWith("artist-track-"),
	);
	await expect.poll(() => activeFocusKey(page)).toBe("artist-track-1");
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeFocusKey(page)).toBe("artist-track-2");
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeFocusKey(page)).toBe("artist-load-more");

	// Возврат к первому треку и Enter — переход в детали.
	await pressUntilFocusKey(page, "ArrowUp", (key) => key === "artist-track-1");
	await expect.poll(() => activeFocusKey(page)).toBe("artist-track-1");
	await page.keyboard.press("Enter");
	await expect(page).toHaveURL(AUDIO_DETAIL_ID_PATTERN);
});

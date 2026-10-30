import type { Page } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

export const VIDEO_LIST_PATTERN = /\/video$/;
export const VIDEO_DETAIL_PATTERN = /\/video\/1$/;
// Ссылка карточки «Продолжить просмотр»: имя собирается из названия,
// остатка и aria-label полосы прогресса, поэтому ищем по фрагменту.
export const CONTINUE_LINK_PATTERN = /Осталось \d{2}:\d{2}/;

const userBody = JSON.stringify({
	id: 1,
	email: "user@example.com",
	is_admin: false,
});

export function videoItem(id: number, title: string) {
	return {
		id,
		title,
		year: 2024,
		description: `Описание ${title}`,
		type: "video",
		duration: 3725,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: `/api/media/${id}/thumb`,
		cover_url: "",
		view_count: 3,
		created_at: "2026-01-01T00:00:00Z",
	};
}

export function listBody(items: ReturnType<typeof videoItem>[], total: number) {
	return JSON.stringify({ items, total, limit: 24, offset: 0 });
}

export function progressItem(
	id: number,
	media: ReturnType<typeof videoItem>,
	position: number,
) {
	return {
		id,
		user_id: 1,
		media_id: media.id,
		position,
		duration: 3725,
		completed: false,
		updated_at: "2026-01-01T00:00:00Z",
		media,
	};
}

// 1×1 прозрачный PNG: превью должно декодироваться как настоящая картинка.
export const PIXEL_PNG = Buffer.from(
	// biome-ignore lint/security/noSecrets: это картинка-фикстура, а не секрет.
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
	"base64",
);

export async function stubAuthedSession(page: Page) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: userBody,
		}),
	);
	await stubEmptyLibraryMeta(page);
}
export async function stubVideoApi(page: Page) {
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) => {
			const url = new URL(route.request().url());
			const q = url.searchParams.get("q") ?? "";
			const items =
				q === ""
					? [videoItem(1, "Первый фильм"), videoItem(2, "Второй фильм")]
					: [];
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: listBody(items, items.length),
			});
		},
	);
	await page.route("**/api/media/1", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(videoItem(1, "Первый фильм")),
		}),
	);
	await page.route("**/api/media/1/subs", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify([{ lang: "ru", url: "/api/media/1/subs/ru" }]),
		}),
	);
	// Блок «Продолжить просмотр» не должен зависеть от живого бэкенда.
	await page.route(
		(url) => url.pathname === "/api/progress",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 20, offset: 0 }),
			}),
	);
}

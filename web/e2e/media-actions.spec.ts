import { expect, type Page, test } from "@playwright/test";
import { stubEmptyLibraryMeta } from "./stubs";

const VIDEO_LIST_PATTERN = /\/video$/;
const VIDEO_DETAIL_PATTERN = /\/video\/1$/;
const AUDIO_TRACK_PATTERN = /\/audio$/;
const COLLECTION_DETAIL_PATTERN = /\/collections\/1$/;

const PIXEL_PNG = Buffer.from(
	// biome-ignore lint/security/noSecrets: это картинка-фикстура, а не секрет.
	"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
	"base64",
);

function videoItem(id: number, title: string) {
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
		source_url: "https://example.com/source",
	};
}

function audioItem(id: number, title: string) {
	return {
		id,
		title,
		filename: `track-${id}.mp3`,
		year: 2024,
		description: "",
		type: "audio",
		artists: [],
		album: "",
		genre: "",
		duration: 120,
		width: 0,
		height: 0,
		file_size: 100,
		thumbnail_url: "",
		cover_url: "",
		view_count: 1,
		created_at: "2026-01-01T00:00:00Z",
	};
}

function collectionItem(id: number, name: string) {
	return {
		id,
		user_id: 1,
		name,
		type: "video",
		parent_id: null,
		created_at: "2026-01-01T00:00:00Z",
		updated_at: "2026-01-01T00:00:00Z",
	};
}

async function stubAdmin(page: Page) {
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
	await page.route(
		(url) => url.pathname === "/api/progress",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 20, offset: 0 }),
			}),
	);
	await stubEmptyLibraryMeta(page);
}

async function stubVideoDetail(page: Page) {
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 24, offset: 0 }),
			}),
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
			body: "[]",
		}),
	);
	await page.route("**/api/progress/1", (route) =>
		route.fulfill({
			status: 404,
			contentType: "application/json",
			body: JSON.stringify({ error: "not found" }),
		}),
	);
	await page.route("**/api/media/1/thumb", (route) =>
		route.fulfill({
			status: 404,
			contentType: "application/json",
			body: JSON.stringify({ error: "no thumb" }),
		}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/extracted",
		(route) =>
			route.fulfill({
				status: 404,
				contentType: "application/json",
				body: JSON.stringify({ error: "no track" }),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/artists",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [] }),
			}),
	);
}

test("метаданные: правка названия на детальной видео", async ({ page }) => {
	await stubAdmin(page);
	await stubVideoDetail(page);
	// Заголовок переживает рефетч после успеха: стаб хранит состояние,
	// как настоящий бэкенд, иначе инвалидация вернёт старое название.
	let currentTitle = "Первый фильм";
	await page.route("**/api/media/1", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(videoItem(1, currentTitle)),
		}),
	);
	const metadataBodies: string[] = [];
	await page.route(
		(url) => url.pathname === "/api/metadata/1",
		(route) => {
			const raw = route.request().postData() ?? "";
			metadataBodies.push(raw);
			try {
				currentTitle = (JSON.parse(raw) as { title?: unknown }).title as string;
			} catch {
				// Тело проверится ниже; здесь не падаем.
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(videoItem(1, currentTitle)),
			});
		},
	);

	await page.goto("/video/1");
	await expect(page).toHaveURL(VIDEO_DETAIL_PATTERN);
	await page.getByRole("button", { name: "Изменить" }).click();
	// Ссылка предзаполнена из медиа, а не пустая.
	await expect(page.getByLabel("Ссылка на источник")).toHaveValue(
		"https://example.com/source",
	);
	await page.getByLabel("Название").fill("Новое название");
	await page.getByRole("button", { name: "Сохранить" }).click();

	// Ждём успех (закрытие модалки), а не отправку: заголовок
	// обновляется в onSuccess той же очередью микротасков.
	await expect(page.getByRole("dialog")).toBeHidden();
	await expect(
		page.getByRole("heading", { level: 1, name: "Новое название" }),
	).toBeVisible();
	const body = JSON.parse(metadataBodies[0] ?? "{}") as Record<string, unknown>;
	expect(body.title).toBe("Новое название");
	// Редактор отправляет текущие значения: пустой genre — очистка.
	expect(body.genre).toBe("");
	expect(body.description).toBe("Описание Первый фильм");
	// Ссылку не трогали — она не отправляется и не стирается.
	expect(body).not.toHaveProperty("source_url");

	// Осознанная очистка: пустое поле при непустой исходной уходит "".
	await page.getByRole("button", { name: "Изменить" }).click();
	await page.getByLabel("Ссылка на источник").fill("");
	await page.getByRole("button", { name: "Сохранить" }).click();
	await expect.poll(() => metadataBodies.length).toBe(2);
	const cleared = JSON.parse(metadataBodies[1] ?? "{}") as Record<
		string,
		unknown
	>;
	expect(cleared.source_url).toBe("");
});

test("обложка: замена уходит multipart-полем cover", async ({ page }) => {
	await stubAdmin(page);
	await stubVideoDetail(page);
	let mediaGets = 0;
	await page.route(
		(url) => url.pathname === "/api/media/1",
		(route) => {
			if (route.request().method() === "GET") {
				mediaGets += 1;
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(videoItem(1, "Первый фильм")),
			});
		},
	);
	let coverBody: Buffer<ArrayBufferLike> = Buffer.alloc(0);
	let coverContentType = "";
	await page.route(
		(url) => url.pathname === "/api/media/1/cover",
		async (route) => {
			coverBody = route.request().postDataBuffer() ?? Buffer.alloc(0);
			coverContentType =
				(await route.request().headerValue("content-type")) ?? "";
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ cover_url: "/api/media/1/cover" }),
			});
		},
	);

	await page.goto("/video/1");
	await page.getByRole("button", { name: "Заменить обложку" }).click();
	// biome-ignore lint/security/noSecrets: CSS-селектор, не секрет.
	await page.locator('input[type="file"]').setInputFiles({
		name: "cover.png",
		mimeType: "image/png",
		buffer: PIXEL_PNG,
	});

	await expect.poll(() => coverBody.length).toBeGreaterThan(0);
	expect(coverContentType).toContain("multipart/form-data");
	expect(coverBody.toString()).toContain('name="cover"');
	expect(coverBody.toString()).toContain("cover.png");
	// Инвалидация после PUT: детальная перечитывает медиа и снова
	// запрашивает обложку (сервер отдаёт no-cache — придёт новый файл).
	await expect.poll(() => mediaGets).toBeGreaterThan(1);
});

test("извлечение: джоб доводится до трека и ссылки", async ({ page }) => {
	await stubAdmin(page);
	await stubVideoDetail(page);
	await page.route("**/api/media/9", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify(audioItem(9, "Извлечённый трек")),
		}),
	);
	await page.route("**/api/progress/9", (route) =>
		route.fulfill({
			status: 404,
			contentType: "application/json",
			body: JSON.stringify({ error: "not found" }),
		}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/extract",
		(route) =>
			route.fulfill({
				status: 202,
				contentType: "application/json",
				body: JSON.stringify({ job_id: 3 }),
			}),
	);
	let polls = 0;
	await page.route(
		(url) => url.pathname === "/api/media/extract/3",
		(route) => {
			polls += 1;
			const done = polls > 1;
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					id: 3,
					status: done ? "done" : "processing",
					error: null,
					media: done ? audioItem(9, "Извлечённый трек") : null,
				}),
			});
		},
	);

	await page.goto("/video/1");
	await page.getByRole("button", { name: "Извлечь аудио" }).click();
	await page
		.getByRole("dialog")
		.getByRole("button", { name: "Извлечь аудио" })
		.click();

	await expect(page.getByText("Извлечение аудио…")).toBeVisible();
	await expect(page.getByRole("button", { name: "Открыть трек" })).toBeVisible({
		timeout: 15_000,
	});
	await page.getByRole("button", { name: "Открыть трек" }).click();
	await expect(page).toHaveURL(AUDIO_TRACK_PATTERN);
});

test("удаление медиа уводит в раздел", async ({ page }) => {
	await stubAdmin(page);
	await stubVideoDetail(page);
	let deletedId = 0;
	await page.route(
		(url) => url.pathname === "/api/media/1",
		(route) => {
			if (route.request().method() === "DELETE") {
				deletedId = 1;
				return route.fulfill({
					status: 200,
					contentType: "application/json",
					body: JSON.stringify({ message: "Media moved to trash" }),
				});
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(videoItem(1, "Первый фильм")),
			});
		},
	);

	await page.goto("/video/1");
	await expect(page).toHaveURL(VIDEO_DETAIL_PATTERN);
	await page.getByRole("button", { name: "Удалить" }).click();
	await page
		.getByRole("dialog")
		.getByRole("button", { name: "Удалить" })
		.click();

	expect(deletedId).toBe(1);
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
});

test("видео не попадает в аудио-очередь", async ({ page }) => {
	await stubAdmin(page);
	await stubVideoDetail(page);

	await page.goto("/video/1");
	await expect(page).toHaveURL(VIDEO_DETAIL_PATTERN);

	// Кнопки «В очередь» на видео больше нет: аудио-плеер не должен
	// пытаться проиграть видео как трек.
	await expect(page.getByRole("button", { name: "В очередь" })).toHaveCount(0);
	await expect(page.locator(".audio-mini-player")).toHaveCount(0);
});

test("перенос элемента в другую коллекцию", async ({ page }) => {
	await stubAdmin(page);
	const items = [videoItem(1, "Первый фильм")];
	await page.route(
		(url) => url.pathname === "/api/collections",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify([
					collectionItem(1, "Исходная"),
					collectionItem(2, "Целевая"),
				]),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/collections/1/items",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(items),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/collections/2/items",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: "[]",
			}),
	);
	let moveBody = "";
	await page.route(
		(url) => url.pathname === "/api/collections/1/items/move",
		(route) => {
			moveBody = route.request().postData() ?? "";
			items.length = 0;
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ id: 1, collection_id: 2 }),
			});
		},
	);

	await page.goto("/collections/1");
	await expect(page).toHaveURL(COLLECTION_DETAIL_PATTERN);
	await expect(page.getByText("Первый фильм")).toBeVisible();
	await page.getByRole("button", { name: "Ещё" }).click();
	await page
		.getByRole("menuitem", { name: "Перенести в другую коллекцию" })
		.click();
	await page.getByRole("button", { name: "Целевая" }).click();

	expect(JSON.parse(moveBody)).toEqual({
		media_id: 1,
		to_collection_id: 2,
	});
	await expect(page.getByText("Первый фильм")).toBeHidden();
});
test("загрузка сразу кладёт файл в выбранную коллекцию", async ({ page }) => {
	await stubAdmin(page);
	await page.route(
		(url) => url.pathname === "/api/collections",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify([collectionItem(5, "Пачка")]),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/upload",
		(route) =>
			route.fulfill({
				status: 202,
				contentType: "application/json",
				body: JSON.stringify({ job_id: 5, job_type: "transcode" }),
			}),
	);
	let polls = 0;
	await page.route(
		(url) => url.pathname === "/api/media/transcodes/5",
		(route) => {
			polls += 1;
			const done = polls > 1;
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					id: 5,
					status: done ? "done" : "processing",
					error: null,
					media: done ? videoItem(7, "Залитый фильм") : null,
					progress: done ? 100 : 40,
				}),
			});
		},
	);
	let collectionBody = "";
	await page.route(
		(url) => url.pathname === "/api/collections/5/items",
		(route) => {
			if (route.request().method() === "POST") {
				collectionBody = route.request().postData() ?? "";
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: route.request().method() === "POST" ? "{}" : "[]",
			});
		},
	);

	await page.goto("/upload?type=video");
	await page.getByRole("combobox").click();
	await page.getByRole("option", { name: "Пачка" }).click();
	// biome-ignore lint/security/noSecrets: CSS-селектор, не секрет.
	await page.locator('input[type="file"]').setInputFiles({
		name: "movie.mp4",
		mimeType: "video/mp4",
		buffer: Buffer.from("fake video"),
	});

	await expect.poll(() => collectionBody !== "").toBe(true);
	expect(JSON.parse(collectionBody)).toEqual({ media_id: 7 });
});

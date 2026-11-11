import { expect, type Page, test } from "@playwright/test";

const PROGRESS_ID_PATTERN = /^\/api\/progress\/\d+$/;
const STREAM_PATTERN = /^\/api\/media\/\d+\/stream$/;
const RANGE_PATTERN = /^bytes=(\d+)-(\d*)$/;
const PLAYER_PATTERN = /\/player$/;
const AUDIO_LIST_PATTERN = /\/audio$/;

const LYRICS_BODY = {
	id: 1,
	media_id: 1,
	lyrics_text: "Строка текста",
	translation: "Перевод строки",
	sync_data: "",
	source: "user",
	created_at: "2026-01-01T00:00:00Z",
	updated_at: "2026-01-01T00:00:00Z",
};

// biome-ignore lint/security/noSecrets: LRC-фикстуры, а не секреты.
const SYNC_TEXT = "Первая\nВторая";
// biome-ignore lint/security/noSecrets: LRC-фикстура, а не секрет.
const SYNC_DATA = "[00:00.10] Первая\n[00:00.50] Вторая";

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

async function stubPlayer(
	page: Page,
	{ admin = false }: { admin?: boolean } = {},
) {
	await page.route("**/api/auth/me", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({
				id: 1,
				email: "user@example.com",
				is_admin: admin,
			}),
		}),
	);
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
		(url) => url.pathname === "/api/collections",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: "[]",
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/favorites",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({ items: [], total: 0, limit: 200, offset: 0 }),
			}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/lyrics",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(LYRICS_BODY),
			}),
	);
	// У второго трека текста нет: редактор должен показать «Добавить текст».
	await page.route(
		(url) => url.pathname === "/api/media/2/lyrics",
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

test("аудиоплеер: очередь, мини-плеер и текст", async ({ page }) => {
	await stubPlayer(page);
	await page.goto("/audio");

	await page.getByRole("button", { name: "Слушать" }).first().click();
	await expect(page).toHaveURL(PLAYER_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Первый трек" }),
	).toBeVisible();
	await expect(page.getByText("Строка текста")).toBeVisible();
	await expect(
		page.getByRole("slider", { name: "Позиция воспроизведения" }),
	).toBeVisible();
	await expect(page.getByRole("slider", { name: "Громкость" })).toBeVisible();
	await expect(page.getByTestId("player-prev")).toBeVisible();
	await expect(page.getByTestId("player-next")).toBeVisible();

	await page.getByTestId("player-queue-tab").click();
	await expect(page.getByText("Второй трек")).toBeVisible();

	await page.getByRole("button", { name: "К аудио" }).click();
	await expect(page).toHaveURL(AUDIO_LIST_PATTERN);
	await expect(
		page.getByRole("button", { name: "Закрыть плеер" }),
	).toBeVisible();
});

test("текст: пустое значение сохраняется как очистка, редактор не переезжает на другой трек", async ({
	page,
}) => {
	await stubPlayer(page, { admin: true });
	const saved: unknown[] = [];
	// Регистрируется после stubPlayer, поэтому перехватывает запросы первым.
	await page.route(
		(url) => url.pathname === "/api/media/1/lyrics",
		(route) => {
			if (route.request().method() === "PUT") {
				saved.push(route.request().postDataJSON());
			}
			return route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify(LYRICS_BODY),
			});
		},
	);

	await page.goto("/audio");
	await page.getByRole("button", { name: "Слушать" }).first().click();
	await expect(page).toHaveURL(PLAYER_PATTERN);
	await expect(page.getByText("Строка текста")).toBeVisible();

	// Очистка текста: без флага clear бэкенд оставил бы прежний текст.
	await page.getByRole("button", { name: "Редактировать" }).click();
	await page.getByRole("textbox").fill("");
	await page.getByRole("button", { name: "Сохранить" }).click();
	await expect.poll(() => saved.length).toBe(1);
	expect(saved[0]).toMatchObject({ lyrics_text: "", clear: true });
	// Ждём именно успех (закрытие редактора), а не отправку: иначе
	// onSuccess первого сохранения закроет редактор посреди черновика.
	await expect(page.getByRole("textbox")).toHaveCount(0);

	// Черновик начат на первом треке, но трек переключили: редактор
	// должен закрыться, а не сохранить черновик второму треку.
	await page.getByRole("button", { name: "Редактировать" }).click();
	await page.getByRole("textbox").fill("Черновик");
	await page.getByTestId("player-next").click();
	await expect(
		page.getByRole("heading", { level: 1, name: "Второй трек" }),
	).toBeVisible();
	await expect(page.getByRole("textbox")).toHaveCount(0);
	await expect(
		page.getByRole("button", { name: "Добавить текст" }),
	).toBeVisible();
});

test("текст: пока текст не загружен, редактор недоступен", async ({ page }) => {
	await stubPlayer(page, { admin: true });
	// Регистрируется после stubPlayer, поэтому перехватывает запросы первым.
	await page.route(
		(url) => url.pathname === "/api/media/1/lyrics",
		(route) =>
			route.fulfill({
				status: 500,
				contentType: "application/json",
				body: JSON.stringify({ error: "boom" }),
			}),
	);

	await page.goto("/audio");
	await page.getByRole("button", { name: "Слушать" }).first().click();
	await expect(
		page.getByRole("heading", { level: 1, name: "Первый трек" }),
	).toBeVisible();
	await expect(page.getByText("Не удалось загрузить текст")).toBeVisible();
	// Сохранение без загруженного перевода/синхронизации стёрло бы их.
	await expect(page.getByRole("button", { name: "Редактировать" })).toHaveCount(
		0,
	);
	await expect(
		page.getByRole("button", { name: "Добавить текст" }),
	).toHaveCount(0);
});

test("аудио продолжает с сохранённой позиции", async ({ page }) => {
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
	await page.route(
		(url) => url.pathname === "/api/media",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [audioItem(1, "Первый трек")],
					total: 1,
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
		(url) => url.pathname === "/api/progress/1",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					id: 1,
					user_id: 1,
					media_id: 1,
					position: 30,
					duration: 120,
					completed: false,
					updated_at: "2026-01-01T00:00:00Z",
				}),
			}),
	);
	await page.route("**/api/collections", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: "[]",
		}),
	);
	await page.route("**/api/favorites", (route) =>
		route.fulfill({
			status: 200,
			contentType: "application/json",
			body: JSON.stringify({ items: [], total: 0, limit: 200, offset: 0 }),
		}),
	);
	await page.route(
		(url) => url.pathname === "/api/media/1/lyrics",
		(route) =>
			route.fulfill({
				status: 404,
				contentType: "application/json",
				body: JSON.stringify({ error: "not found" }),
			}),
	);
	// Минута тишины: сохранённые 0:30 обязаны попасть внутрь файла.
	// Отдаём с поддержкой Range: без неё Chromium считает поток
	// неseekable и молча игнорирует восстановление позиции — как и
	// положено, а тест проверяет именно восстановление.
	await page.route(
		(url) => url.pathname === "/api/media/1/stream",
		(route) => {
			const stream = silentWav(60);
			const range = route.request().headers().range;
			if (range === undefined) {
				return route.fulfill({
					status: 200,
					contentType: "audio/wav",
					headers: { "Accept-Ranges": "bytes" },
					body: stream,
				});
			}
			const match = RANGE_PATTERN.exec(range);
			if (match === null) {
				return route.fulfill({ status: 416, body: "bad range" });
			}
			const start = Number(match[1]);
			const end =
				match[2] === ""
					? stream.length - 1
					: Math.min(Number(match[2]), stream.length - 1);
			return route.fulfill({
				status: 206,
				contentType: "audio/wav",
				headers: {
					"Accept-Ranges": "bytes",
					"Content-Range": `bytes ${start}-${end}/${stream.length}`,
					"Content-Length": String(end - start + 1),
				},
				body: stream.subarray(start, end + 1),
			});
		},
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

	await page.goto("/audio");
	await page.getByRole("button", { name: "Слушать" }).first().click();
	await expect(page).toHaveURL(PLAYER_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Первый трек" }),
	).toBeVisible();
	await expect
		.poll(
			async () =>
				page.evaluate(() => document.querySelector("audio")?.currentTime ?? -1),
			{ timeout: 15000 },
		)
		.toBeGreaterThanOrEqual(29);
});

test("текст: синхронные строки подсвечиваются по позиции", async ({ page }) => {
	await stubPlayer(page);
	// Регистрируется после stubPlayer, поэтому перехватывает запросы первым.
	await page.route(
		(url) => url.pathname === "/api/media/1/lyrics",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					...LYRICS_BODY,
					lyrics_text: SYNC_TEXT,
					sync_data: SYNC_DATA,
				}),
			}),
	);

	await page.goto("/audio");
	await page.getByRole("button", { name: "Слушать" }).first().click();
	await expect(page).toHaveURL(PLAYER_PATTERN);
	await expect(page.getByRole("listitem").first()).toBeVisible();
	// Позиция тикает: первая строка становится текущей почти сразу.
	const active = page.locator('[aria-current="true"]');
	await expect(active).toBeVisible({ timeout: 8000 });
	await expect(active).toContainText("Первая");
});

function progressEntry(
	id: number,
	media: ReturnType<typeof audioItem>,
	position: number,
	completed = false,
) {
	return {
		id,
		user_id: 1,
		media_id: media.id,
		position,
		duration: media.duration,
		completed,
		updated_at: "2026-01-01T00:00:00Z",
		media,
	};
}

test("сид не затирает очередь, начатую до ответа сервера", async ({ page }) => {
	await stubPlayer(page);
	// Долгий ответ: пользователь успевает нажать раньше резолва.
	await page.route(
		(url) => url.pathname === "/api/progress",
		async (route) => {
			await new Promise((resolve) => setTimeout(resolve, 800));
			await route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [progressEntry(2, audioItem(2, "Второй трек"), 40)],
					total: 1,
					limit: 20,
					offset: 0,
				}),
			});
		},
	);
	// Длинный файл: секундный стаб закончился бы и увёл на второй трек.
	await page.route(
		(url) => STREAM_PATTERN.test(url.pathname),
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "audio/wav",
				body: silentWav(60),
			}),
	);

	await page.goto("/audio");
	await page.getByRole("button", { name: "Слушать" }).first().click();
	await expect(page).toHaveURL(PLAYER_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Первый трек" }),
	).toBeVisible();
	// Ответ пришёл позже — очередь пользователя уцелела.
	await page.waitForTimeout(1200);
	await expect(
		page.getByRole("heading", { level: 1, name: "Первый трек" }),
	).toBeVisible();
});

test("сид пропускает завершённый трек к старому недослушанному", async ({
	page,
}) => {
	await stubPlayer(page);
	await page.route(
		(url) => url.pathname === "/api/progress",
		(route) =>
			route.fulfill({
				status: 200,
				contentType: "application/json",
				body: JSON.stringify({
					items: [
						// Самый свежий — дослушанный: сид идёт дальше по списку.
						progressEntry(3, audioItem(2, "Второй трек"), 120, true),
						progressEntry(1, audioItem(1, "Первый трек"), 30),
					],
					total: 2,
					limit: 20,
					offset: 0,
				}),
			}),
	);

	await page.goto("/audio");
	const miniPlayer = page.locator(".audio-mini-player");
	await expect(miniPlayer).toBeVisible();
	await expect(miniPlayer.getByText("Первый трек")).toBeVisible();
});

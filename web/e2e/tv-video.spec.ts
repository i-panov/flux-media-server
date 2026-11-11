import { expect, type Page, test } from "@playwright/test";
import { stubAuthedSession, stubVideoApi, videoItem } from "./video-fixtures";

const VIDEO_LIST_PATTERN = /\/video(\?|$)/;
const VIDEO_DETAIL_ID_PATTERN = /\/video\/2(\?|$)/;

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

// Реального потока нет: play/pause/currentTime подменяем, чтобы OSD
// проверялся без медиа-декодера и autoplay-политики.
async function stubMediaElement(page: Page) {
	await page.addInitScript(() => {
		let currentTime = 0;
		let paused = true;
		Object.defineProperty(HTMLMediaElement.prototype, "currentTime", {
			configurable: true,
			get() {
				return currentTime;
			},
			set(value: number) {
				currentTime = value;
			},
		});
		Object.defineProperty(HTMLMediaElement.prototype, "duration", {
			configurable: true,
			get() {
				return 3725;
			},
		});
		Object.defineProperty(HTMLMediaElement.prototype, "paused", {
			configurable: true,
			get() {
				return paused;
			},
		});
		let playCalls = 0;
		let pauseCalls = 0;
		(window as unknown as Record<string, number>).__playCalls = 0;
		(window as unknown as Record<string, number>).__pauseCalls = 0;
		Object.defineProperty(HTMLMediaElement.prototype, "play", {
			configurable: true,
			value(this: HTMLMediaElement) {
				playCalls += 1;
				(window as unknown as Record<string, number>).__playCalls = playCalls;
				paused = false;
				this.dispatchEvent(new Event("play"));
				return Promise.resolve();
			},
		});
		Object.defineProperty(HTMLMediaElement.prototype, "pause", {
			configurable: true,
			value(this: HTMLMediaElement) {
				pauseCalls += 1;
				(window as unknown as Record<string, number>).__pauseCalls = pauseCalls;
				paused = true;
				this.dispatchEvent(new Event("pause"));
			},
		});
	});
}

function activeFocusKey(page: Page): Promise<string> {
	return page.evaluate(
		() => document.activeElement?.getAttribute("data-tv-focus-key") ?? "",
	);
}

function videoState(page: Page) {
	return page.evaluate(() => {
		const video = document.querySelector("video");
		return {
			paused: video?.paused ?? true,
			currentTime: video?.currentTime ?? -1,
			volume: video?.volume ?? -1,
			muted: video?.muted ?? false,
			playCalls:
				(window as unknown as { __playCalls?: number }).__playCalls ?? 0,
			pauseCalls:
				(window as unknown as { __pauseCalls?: number }).__pauseCalls ?? 0,
		};
	});
}

async function openSecondVideo(page: Page) {
	await page.goto("/video?tv=1");
	// Переход карточкой, а не Enter: сам D-pad списка уже покрыт tv.spec,
	// здесь важно стабильно открыть детали и оставить запись в истории.
	await page.getByRole("link", { name: "Второй фильм" }).click();
	await expect(page).toHaveURL(VIDEO_DETAIL_ID_PATTERN);
	await expect(
		page.getByRole("heading", { level: 1, name: "Второй фильм" }),
	).toBeVisible();
	// ТВ: нативных контролов нет, вместо них OSD, фокус на play.
	await expect(page.locator("video")).not.toHaveAttribute("controls", "");
	await expect(page.getByTestId("tv-video-osd")).toBeVisible();
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-play");
}

test("ТВ: видео OSD — play/pause, seek и Back", async ({ page }) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");
	await stubMediaElement(page);
	await openSecondVideo(page);

	// Enter на кнопке play — воспроизведение, повторно — пауза.
	await page.keyboard.press("Enter");
	await expect.poll(async () => (await videoState(page)).paused).toBe(false);
	await page.keyboard.press("Enter");
	await expect.poll(async () => (await videoState(page)).paused).toBe(true);

	// D-pad: вправо/влево — seek на 10 секунд.
	await page.keyboard.press("ArrowRight");
	await expect.poll(async () => (await videoState(page)).currentTime).toBe(10);
	// Стрелка сикает, но не уводит spatial-фокус с play.
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-play");
	await page.keyboard.press("ArrowLeft");
	await expect.poll(async () => (await videoState(page)).currentTime).toBe(0);

	// Media-клавиша пульта.
	await page.evaluate(() => {
		window.dispatchEvent(
			new KeyboardEvent("keydown", { key: "MediaPlayPause" }),
		);
	});
	await expect.poll(async () => (await videoState(page)).paused).toBe(false);

	// Back возвращает к списку, а не просто прячет OSD.
	await page.keyboard.press("Escape");
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
	await expect(page.getByText("Первый фильм", { exact: true })).toBeVisible();
});

test("ТВ: OSD — D-pad уводит с play, громкость, M и F", async ({ page }) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");
	await stubMediaElement(page);
	await openSecondVideo(page);

	// На паузе OSD не автоскрывается.
	await page.waitForTimeout(3500);
	await expect(page.getByTestId("tv-video-osd")).toHaveAttribute(
		"data-visible",
		"true",
	);

	// play → down → mute → right → volume: слайдер доступен с пульта.
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-mute");
	await page.keyboard.press("ArrowRight");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-volume");

	// Горизонталь на слайдере — нативная громкость, фокус не уходит.
	const volumeBefore = (await videoState(page)).volume;
	await page.keyboard.press("ArrowLeft");
	await expect
		.poll(async () => (await videoState(page)).volume)
		.toBeLessThan(volumeBefore);
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-volume");

	// Вертикаль на volume уводит spatial-фокус, но не меняет значение.
	const volumeBeforeUp = (await videoState(page)).volume;
	await page.keyboard.press("ArrowUp");
	await expect.poll(() => activeFocusKey(page)).not.toBe("video-osd-volume");
	expect((await videoState(page)).volume).toBe(volumeBeforeUp);

	// Добираемся до timeline и проверяем такой же выход по вертикали.
	await page.keyboard.press("ArrowUp");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-back");
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-timeline");
	const timeBeforeTimeline = (await videoState(page)).currentTime;
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeFocusKey(page)).not.toBe("video-osd-timeline");
	expect((await videoState(page)).currentTime).toBe(timeBeforeTimeline);

	// M — mute, F — fullscreen.
	await page.keyboard.press("m");
	await expect.poll(async () => (await videoState(page)).muted).toBe(true);
	await page.keyboard.press("m");
	await expect.poll(async () => (await videoState(page)).muted).toBe(false);

	// F — fullscreen; Back сначала выходит из fullscreen, страница остаётся.
	await page.keyboard.press("f");
	await expect
		.poll(() => page.evaluate(() => document.fullscreenElement !== null))
		.toBe(true);
	await page.keyboard.press("Escape");
	await expect
		.poll(() => page.evaluate(() => document.fullscreenElement !== null))
		.toBe(false);
	await expect(page).toHaveURL(VIDEO_DETAIL_ID_PATTERN);

	// Второй Back уже уходит к списку.
	await page.keyboard.press("Escape");
	await expect(page).toHaveURL(VIDEO_LIST_PATTERN);
});

test("ТВ: OSD автоскрывается, клик по скрытому таймлайну не сикает", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");
	await stubMediaElement(page);
	await openSecondVideo(page);

	// Запускаем воспроизведение: только играющий OSD автоскрывается.
	await page.keyboard.press("Enter");
	await expect.poll(async () => (await videoState(page)).paused).toBe(false);
	const osd = page.getByTestId("tv-video-osd");
	await expect
		.poll(() => osd.getAttribute("data-visible"), { timeout: 6000 })
		.toBe("false");
	await expect(osd).toHaveAttribute("aria-hidden", "true");
	await expect(osd).toHaveAttribute("inert", "");

	const before = (await videoState(page)).currentTime;
	// OSD скрыт (inert/aria-hidden), поэтому getByRole его не видит:
	// координаты берём у первого слайдера в DOM.
	const timeline = page.locator(".tv-video-osd .mantine-Slider-root").first();
	const box = await timeline.boundingBox();
	expect(box).not.toBeNull();
	if (box === null) {
		return;
	}
	const x = box.x + box.width / 2;
	const y = box.y + box.height / 2;

	// Клик, который сам был первым pointerdown на скрытой панели,
	// только показывает OSD и не уходит в seek. pointermove здесь
	// намеренно не шлём: он бы уже показал панель.
	await page.evaluate(
		({ px, py }) => {
			const target = document.elementFromPoint(px, py) ?? document.body;
			target.dispatchEvent(
				new PointerEvent("pointerdown", {
					bubbles: true,
					cancelable: true,
					clientX: px,
					clientY: py,
					pointerType: "mouse",
				}),
			);
			target.dispatchEvent(
				new MouseEvent("mousedown", {
					bubbles: true,
					cancelable: true,
					clientX: px,
					clientY: py,
				}),
			);
			target.dispatchEvent(
				new MouseEvent("mouseup", {
					bubbles: true,
					cancelable: true,
					clientX: px,
					clientY: py,
				}),
			);
			target.dispatchEvent(
				new MouseEvent("click", {
					bubbles: true,
					cancelable: true,
					clientX: px,
					clientY: py,
					detail: 1,
				}),
			);
		},
		{ px: x, py: y },
	);
	await expect(osd).toHaveAttribute("data-visible", "true");
	expect((await videoState(page)).currentTime).toBe(before);

	// Снова автоскрытие. Теперь pointermove показывает панель, и первый
	// же клик после него должен работать, а не съедаться.
	await expect
		.poll(() => osd.getAttribute("data-visible"), { timeout: 6000 })
		.toBe("false");
	await page.mouse.move(x, y);
	await expect(osd).toHaveAttribute("data-visible", "true");
	await page.mouse.click(x, y);
	await expect
		.poll(async () => (await videoState(page)).currentTime)
		.toBeGreaterThan(before);
});

test("ТВ: вертикальный уход со слайдера не блокирует pointer seek", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");
	await stubMediaElement(page);
	await openSecondVideo(page);

	const timeline = page.locator(".tv-video-osd .mantine-Slider-root").first();
	const box = await timeline.boundingBox();
	expect(box).not.toBeNull();
	if (box === null) {
		return;
	}
	const y = box.y + box.height / 2;
	const clickAt = async (fraction: number) => {
		await page.mouse.click(box.x + box.width * fraction, y);
	};

	await clickAt(0.5);
	await expect
		.poll(async () => (await videoState(page)).currentTime)
		.toBeGreaterThan(500);

	// Вертикальный уход со слайдера: keyup уходит на другую цель.
	await page.keyboard.press("ArrowUp");

	// Следующий pointer seek должен работать, а не блокироваться
	// залипшим sliderVerticalKey.
	await clickAt(0.8);
	await expect
		.poll(async () => (await videoState(page)).currentTime)
		.toBeGreaterThan(2500);
});

test("ТВ: после автоскрытия фокус возвращается на play, не в слайдер", async ({
	page,
}) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");
	await stubMediaElement(page);
	await openSecondVideo(page);

	// Уводим фокус на volume и даём играющему OSD автоскрыться.
	await page.keyboard.press("Enter");
	await page.keyboard.press("ArrowDown");
	await page.keyboard.press("ArrowRight");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-volume");
	const osd = page.getByTestId("tv-video-osd");
	await expect
		.poll(() => osd.getAttribute("data-visible"), { timeout: 6000 })
		.toBe("false");

	// Первый Enter только показывает OSD и возвращает фокус на play:
	// ни play, ни pause не вызываются.
	const beforeShow = await videoState(page);
	await page.keyboard.press("Enter");
	await expect(osd).toHaveAttribute("data-visible", "true");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-play");
	const afterShow = await videoState(page);
	expect(afterShow.playCalls).toBe(beforeShow.playCalls);
	expect(afterShow.pauseCalls).toBe(beforeShow.pauseCalls);

	// Второй Enter уже переключает play/pause.
	await page.keyboard.press("Enter");
	await expect.poll(async () => (await videoState(page)).paused).toBe(true);
	await page.keyboard.press("Enter");
	await expect.poll(async () => (await videoState(page)).paused).toBe(false);

	// Повторное автоскрытие и показ стрелкой: фокус снова на play,
	// громкость не меняется.
	const volumeBeforeArrow = (await videoState(page)).volume;
	await expect
		.poll(() => osd.getAttribute("data-visible"), { timeout: 6000 })
		.toBe("false");
	await page.keyboard.press("ArrowUp");
	await expect(osd).toHaveAttribute("data-visible", "true");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-play");
	expect((await videoState(page)).volume).toBe(volumeBeforeArrow);
});

test("ТВ: после автоскрытия Enter не дублирует mute", async ({ page }) => {
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");
	await stubMediaElement(page);
	await openSecondVideo(page);

	// Играем, уводим фокус на mute и ждём автоскрытия.
	await page.keyboard.press("Enter");
	await page.keyboard.press("ArrowDown");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-mute");
	const osd = page.getByTestId("tv-video-osd");
	await expect
		.poll(() => osd.getAttribute("data-visible"), { timeout: 6000 })
		.toBe("false");

	// Первый Enter только показывает OSD и возвращает фокус на mute.
	const beforeShow = await videoState(page);
	await page.keyboard.press("Enter");
	await expect(osd).toHaveAttribute("data-visible", "true");
	await expect.poll(() => activeFocusKey(page)).toBe("video-osd-mute");
	const afterShow = await videoState(page);
	expect(afterShow.muted).toBe(false);
	expect(afterShow.playCalls).toBe(beforeShow.playCalls);
	expect(afterShow.pauseCalls).toBe(beforeShow.pauseCalls);

	// Второй Enter переключает только mute, playback не трогает.
	await page.keyboard.press("Enter");
	await expect.poll(async () => (await videoState(page)).muted).toBe(true);
	const afterMute = await videoState(page);
	expect(afterMute.playCalls).toBe(beforeShow.playCalls);
	expect(afterMute.pauseCalls).toBe(beforeShow.pauseCalls);
	expect(afterMute.paused).toBe(false);
});

test("ТВ: OSD скрывает fullscreen, если API недоступен", async ({ page }) => {
	await page.addInitScript(() => {
		Object.defineProperty(Element.prototype, "requestFullscreen", {
			configurable: true,
			value: undefined,
		});
		Object.defineProperty(Element.prototype, "webkitRequestFullscreen", {
			configurable: true,
			value: undefined,
		});
	});
	await stubAuthedSession(page);
	await stubVideoApi(page);
	await stubVideoDetail(page, 2, "Второй фильм");
	await stubMediaElement(page);
	await openSecondVideo(page);

	await expect(page.getByRole("button", { name: "Полный экран" })).toHaveCount(
		0,
	);
	await expect(page.getByTestId("tv-video-play")).toBeVisible();
});

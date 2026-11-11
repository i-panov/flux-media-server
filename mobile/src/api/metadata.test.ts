import { apiFetch, mediaSchema } from "@flux/shared";
import { beforeEach, describe, expect, it, vi } from "vitest";
import {
	artistsQueryKey,
	buildMetadataInput,
	isMetadataDraftDirty,
	isValidSourceUrl,
	type MetadataDraft,
	metadataDraftFromMedia,
	normalizeArtistNames,
	normalizeArtists,
	parseYearInput,
	updateMetadata,
	validateMetadataDraft,
} from "./metadata";

vi.mock("@flux/shared", async (importOriginal) => {
	const actual = await importOriginal<typeof import("@flux/shared")>();
	return { ...actual, apiFetch: vi.fn() };
});

const apiFetchMock = vi.mocked(apiFetch);
const TYLER = "Tyler, The Creator";
const EARTH_WIND = "Earth, Wind & Fire";

beforeEach(() => {
	apiFetchMock.mockReset();
});

describe("normalizeArtists", () => {
	it("читает items и приводит поля к контракту", () => {
		expect(
			normalizeArtists({
				items: [
					{ id: 2, name: "Beta", has_cover: true, updated_at: "2026-01-02" },
					{ id: 1, name: "Alpha" },
				],
			}),
		).toEqual([
			{ id: 1, name: "Alpha", has_cover: false, updated_at: "" },
			{ id: 2, name: "Beta", has_cover: true, updated_at: "2026-01-02" },
		]);
	});

	it("принимает массив без обёртки и сортирует по имени", () => {
		expect(
			normalizeArtists([
				{ id: 1, name: "Zulu" },
				{ id: 2, name: "Alpha" },
			]).map((artist) => artist.name),
		).toEqual(["Alpha", "Zulu"]);
	});

	it("убирает дубликаты по имени и невалидные записи", () => {
		const artists = normalizeArtists({
			items: [
				{ id: 1, name: "Alpha" },
				{ id: 2, name: "Alpha" },
				{ id: 0, name: "Zero" },
				{ id: 3, name: "" },
				null,
				{ id: 4, name: "Beta", unknown: true },
			],
		});
		expect(artists.map((artist) => artist.id)).toEqual([1, 4]);
	});

	it("бросает ошибку на неожиданный ответ", () => {
		expect(() => normalizeArtists(null)).toThrow("Unexpected artists response");
		expect(() => normalizeArtists({ items: "nope" })).toThrow(
			"Unexpected artists response",
		);
	});
});

describe("artistsQueryKey", () => {
	it("совпадает с ключом web", () => {
		expect(artistsQueryKey).toEqual(["artists"]);
	});
});

function mediaFixture(overrides: Record<string, unknown> = {}) {
	return mediaSchema.parse({
		id: 7,
		title: "Исходное название",
		filename: "movie.mkv",
		year: 2020,
		description: "Описание",
		type: "video",
		artists: [
			{ id: 1, name: "Alpha", has_cover: false, updated_at: "" },
			{ id: 2, name: "Beta", has_cover: true, updated_at: "2026-01-01" },
		],
		album: "Альбом",
		genre: "Жанр",
		duration: 120,
		width: 1920,
		height: 1080,
		file_size: 100,
		thumbnail_url: "",
		cover_url: "",
		view_count: 0,
		created_at: "2026-01-01T00:00:00Z",
		source_url: "https://example.com/movie",
		...overrides,
	});
}

function draft(overrides: Partial<MetadataDraft> = {}): MetadataDraft {
	return {
		title: "Название",
		artists: ["Alpha"],
		album: "",
		genre: "",
		year: "",
		description: "",
		sourceUrl: "",
		...overrides,
	};
}

describe("metadataDraftFromMedia", () => {
	it("переносит поля медиа и артистов массивом", () => {
		const media = mediaFixture();
		expect(metadataDraftFromMedia(media)).toEqual({
			title: "Исходное название",
			artists: ["Alpha", "Beta"],
			album: "Альбом",
			genre: "Жанр",
			year: "2020",
			description: "Описание",
			sourceUrl: "https://example.com/movie",
		});
	});

	it("год 0 (неизвестен) остаётся пустым полем", () => {
		expect(metadataDraftFromMedia(mediaFixture({ year: 0 })).year).toBe("");
	});
});

describe("normalizeArtistNames", () => {
	it("не режет имена с запятыми и амперсандами", () => {
		expect(normalizeArtistNames([TYLER, EARTH_WIND])).toEqual([
			TYLER,
			EARTH_WIND,
		]);
	});

	it("обрезает пробелы и выбрасывает пустые значения", () => {
		expect(normalizeArtistNames([" Alpha ", "", "  ", "Beta"])).toEqual([
			"Alpha",
			"Beta",
		]);
	});

	it("схлопывает только точные дубликаты, регистр сохраняет", () => {
		expect(normalizeArtistNames(["Alpha", "Alpha", "alpha"])).toEqual([
			"Alpha",
			"alpha",
		]);
	});
});

describe("parseYearInput", () => {
	it("принимает нижнюю границу, текущий год и текущий + 2", () => {
		expect(parseYearInput("1888", 2026)).toBe(1888);
		expect(parseYearInput("2026", 2026)).toBe(2026);
		expect(parseYearInput("2028", 2026)).toBe(2028);
	});

	it("пустая строка и 0 — осознанная очистка года", () => {
		expect(parseYearInput("", 2026)).toBe(0);
		expect(parseYearInput("  ", 2026)).toBe(0);
		expect(parseYearInput("0", 2026)).toBe(0);
	});

	it("отвергает неверный формат и выход за границы", () => {
		expect(parseYearInput("1887", 2026)).toBeNull();
		expect(parseYearInput("2029", 2026)).toBeNull();
		expect(parseYearInput("20", 2026)).toBeNull();
		expect(parseYearInput("20200", 2026)).toBeNull();
		expect(parseYearInput("abcd", 2026)).toBeNull();
	});
});

// biome-ignore lint/security/noSecrets: имя теста, не секрет.
describe("isValidSourceUrl", () => {
	it("пустая ссылка валидна: так поле очищается", () => {
		expect(isValidSourceUrl("")).toBe(true);
		expect(isValidSourceUrl("   ")).toBe(true);
	});

	it("принимает только полный http(s)-URL с хостом", () => {
		expect(isValidSourceUrl("https://example.com/a?b=1")).toBe(true);
		expect(isValidSourceUrl("http://example.com")).toBe(true);
		expect(isValidSourceUrl("ftp://example.com/file")).toBe(false);
		expect(isValidSourceUrl("example.com/file")).toBe(false);
		expect(isValidSourceUrl("http://")).toBe(false);
		expect(isValidSourceUrl("javascript:alert(1)")).toBe(false);
	});

	it("запрещает credentials и слишком длинные ссылки, как backend", () => {
		// biome-ignore lint/security/noSecrets: тестовый URL с credentials, не секрет.
		expect(isValidSourceUrl("https://user:pass@example.com/a")).toBe(false);
		expect(isValidSourceUrl("http://@example.com/a")).toBe(false);
		expect(isValidSourceUrl(`https://example.com/${"a".repeat(2048)}`)).toBe(
			false,
		);
	});

	it("отвергает некорректные percent-escape, как backend", () => {
		expect(isValidSourceUrl("https://example.com/%zz")).toBe(false);
		expect(isValidSourceUrl("https://example.com/%41")).toBe(true);
	});
});

describe("validateMetadataDraft", () => {
	it("валидный черновик не содержит ошибок", () => {
		expect(validateMetadataDraft(draft(), 2026)).toEqual({
			title: true,
			year: true,
			sourceUrl: true,
		});
	});

	it("пустой title, неверный год и ссылка помечаются", () => {
		expect(
			validateMetadataDraft(
				draft({ title: "   ", year: "20", sourceUrl: "not a url" }),
				2026,
			),
		).toEqual({ title: false, year: false, sourceUrl: false });
	});
});

describe("buildMetadataInput", () => {
	it("обрезает строки и нормализует артистов без split по запятой", () => {
		expect(
			buildMetadataInput(
				draft({
					title: "  Название  ",
					artists: [" Alpha ", "Beta", "Alpha", ""],
					album: "  Альбом ",
					genre: " Жанр ",
					year: " 2024 ",
					description: "  Описание ",
					sourceUrl: " https://example.com/x ",
				}),
			),
		).toEqual({
			title: "Название",
			artists: ["Alpha", "Beta"],
			album: "Альбом",
			genre: "Жанр",
			year: 2024,
			description: "Описание",
			sourceUrl: "https://example.com/x",
		});
	});

	it("не режет имя с запятой при сохранении", () => {
		expect(
			buildMetadataInput(draft({ artists: [TYLER, EARTH_WIND] })).artists,
		).toEqual([TYLER, EARTH_WIND]);
	});

	// biome-ignore lint/security/noSecrets: имя теста, не секрет.
	it("пустой год отправляет 0 (очистка)", () => {
		expect(buildMetadataInput(draft({ year: "" })).year).toBe(0);
	});
});

describe("isMetadataDraftDirty", () => {
	it("не считает изменение пробелов и дублей артистов правкой", () => {
		const initial = draft();
		expect(
			isMetadataDraftDirty(initial, {
				...initial,
				title: "  Название ",
				artists: [" Alpha ", ""],
			}),
		).toBe(false);
	});

	it("видит изменение любого поля", () => {
		const initial = draft();
		expect(isMetadataDraftDirty(initial, { ...initial, album: "Другой" })).toBe(
			true,
		);
		expect(isMetadataDraftDirty(initial, { ...initial, year: "2024" })).toBe(
			true,
		);
	});
});

describe("updateMetadata", () => {
	it("шлёт PUT /metadata/:id с массивом артистов и без undefined-полей", async () => {
		apiFetchMock.mockResolvedValue(mediaFixture());
		const result = await updateMetadata(7, {
			title: "Название",
			artists: [TYLER],
			sourceUrl: undefined,
		});
		expect(result.id).toBe(7);
		expect(apiFetchMock).toHaveBeenCalledTimes(1);
		const [path, init] = apiFetchMock.mock.calls[0] ?? [];
		expect(path).toBe("/metadata/7");
		expect(init?.method).toBe("PUT");
		const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
		expect(body).toEqual({
			title: "Название",
			artists: [TYLER],
		});
		expect(body).not.toHaveProperty("source_url");
	});

	it("пустая строка и 0 очищают, undefined не отправляется", async () => {
		apiFetchMock.mockResolvedValue(mediaFixture());
		await updateMetadata(7, {
			title: "Название",
			artists: [],
			album: undefined,
			genre: "",
			year: 0,
			description: undefined,
			sourceUrl: "",
		});
		const body = JSON.parse(
			String(apiFetchMock.mock.calls[0]?.[1]?.body),
		) as Record<string, unknown>;
		expect(body.genre).toBe("");
		expect(body.year).toBe(0);
		expect(body.source_url).toBe("");
		expect(body).not.toHaveProperty("album");
		expect(body).not.toHaveProperty("description");
	});
});

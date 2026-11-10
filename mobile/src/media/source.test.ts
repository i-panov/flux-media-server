import { type AuthTransport, configureApi, resetApiConfig } from "@flux/shared";
import { afterEach, describe, expect, it } from "vitest";
import {
	authSource,
	coverPath,
	imageSource,
	isHttpSourceUrl,
	streamPath,
	thumbPath,
} from "./source";

const BASE_URL = "https://media.example/api";
const TOKEN = "test-access-token";

function fakeTransport(
	headers: Record<string, string> = { Authorization: `Bearer ${TOKEN}` },
): AuthTransport {
	return {
		authHeaders: async () => headers,
		credentials: () => undefined,
		refresh: async () => {},
	};
}

function configure(baseUrl: string, headers?: Record<string, string>): void {
	configureApi({ baseUrl, transport: fakeTransport(headers) });
}

// Конфиг общий для всего рантайма: после каждого теста возвращаем дефолт,
// иначе порядок тестов начнёт влиять на результат.
afterEach(() => {
	resetApiConfig();
});

describe("media paths", () => {
	it("строит пути стрима, превью и обложки", () => {
		expect(streamPath(42)).toBe("/media/42/stream");
		expect(thumbPath(42)).toBe("/media/42/thumb");
		expect(coverPath(42)).toBe("/media/42/cover");
	});
});

describe("authSource", () => {
	it("добавляет Bearer-заголовок после логина", async () => {
		configure(BASE_URL);

		const source = await authSource(streamPath(7));

		expect(source.headers).toEqual({ Authorization: `Bearer ${TOKEN}` });
		expect(source.uri).toBe(`${BASE_URL}/media/7/stream`);
	});

	it("не даёт двойной слэш при baseUrl с хвостовым слэшем", async () => {
		configure(`${BASE_URL}/`);

		const source = await authSource(thumbPath(7));

		expect(source.uri).toBe(`${BASE_URL}/media/7/thumb`);
		expect(new URL(source.uri).pathname).toBe("/api/media/7/thumb");
	});

	it("добавляет ведущий слэш, если путь его не содержит", async () => {
		configure(BASE_URL);

		const source = await authSource("media/7/cover");

		expect(source.uri).toBe(`${BASE_URL}/media/7/cover`);
	});

	it("без сессии отдаёт пустые заголовки", async () => {
		configure(BASE_URL, {});

		const source = await authSource(streamPath(7));

		expect(source.headers).toEqual({});
	});

	it("не кеширует заголовки между вызовами", async () => {
		let token = "first-token";
		configureApi({
			baseUrl: BASE_URL,
			transport: {
				...fakeTransport(),
				authHeaders: async () => ({ Authorization: `Bearer ${token}` }),
			},
		});

		const first = await authSource(streamPath(1));
		token = "second-token";
		const second = await authSource(streamPath(1));

		expect(first.headers.Authorization).toBe("Bearer first-token");
		expect(second.headers.Authorization).toBe("Bearer second-token");
	});
});

describe("source URL validation", () => {
	it("принимает только абсолютные http(s)-ссылки", () => {
		expect(isHttpSourceUrl("https://example.com/watch?v=1")).toBe(true);
		expect(isHttpSourceUrl("http://example.com")).toBe(true);
		expect(isHttpSourceUrl("  https://example.com/path  ")).toBe(true);
	});

	it("отсекает опасные и относительные схемы", () => {
		expect(isHttpSourceUrl("javascript:alert(1)")).toBe(false);
		expect(isHttpSourceUrl("file:///etc/passwd")).toBe(false);
		expect(isHttpSourceUrl("data:text/html,hi")).toBe(false);
		expect(isHttpSourceUrl("/media/1")).toBe(false);
		expect(isHttpSourceUrl("example.com")).toBe(false);
	});

	it("не пропускает пустую ссылку и URL без хоста", () => {
		expect(isHttpSourceUrl("")).toBe(false);
		expect(isHttpSourceUrl("https://")).toBe(false);
		expect(isHttpSourceUrl("https:///path")).toBe(false);
		expect(isHttpSourceUrl("https://exa mple.com")).toBe(false);
	});
});

describe("imageSource", () => {
	it("возвращает тот же авторизованный source, что authSource", async () => {
		configure(BASE_URL);

		const source = await imageSource(thumbPath(7));

		expect(source).toEqual(await authSource(thumbPath(7)));
		expect(source.headers.Authorization).toBe(`Bearer ${TOKEN}`);
	});
});

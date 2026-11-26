import { getApiConfig } from "@flux/shared";

// Источник для expo-video/expo-audio/expo-image: абсолютный URL и заголовки
// авторизации. Тип структурный, поэтому импортировать сами библиотеки здесь
// не нужно — их source-объекты принимают ту же форму.
export interface AuthSource {
	uri: string;
	headers: Record<string, string>;
}

const TRAILING_SLASHES = /\/+$/;
const API_SUFFIX = /\/api\/?$/i;
const HTTP_URL_START = /^https?:\/\//i;
const LEADING_SLASHES = /^\/+/;

// baseUrl приходит из настроек сервера и может быть с хвостовым слэшем,
// а путь — без ведущего. Склеиваем ровно одним слэшем, чтобы не получить
// `//media` (некоторые серверы и CDN трактуют такой путь иначе).
function joinUrl(baseUrl: string, path: string): string {
	const base = baseUrl.replace(TRAILING_SLASHES, "");
	const suffix = path.replace(LEADING_SLASHES, "");
	return `${base}/${suffix}`;
}

// Токен не кешируется между запросами: authHeaders() читает SecureStore,
// иначе после refresh плеер ходил бы со старым access-токеном. Но при
// монтировании сетки десятки карточек просят заголовки одновременно —
// дедуплицируем один и тот же in-flight запрос.
let headersInflight: Promise<Record<string, string>> | null = null;

function authHeadersOnce(): Promise<Record<string, string>> {
	if (headersInflight === null) {
		headersInflight = getApiConfig()
			.transport.authHeaders()
			.finally(() => {
				headersInflight = null;
			});
	}
	return headersInflight;
}

export async function authSource(path: string): Promise<AuthSource> {
	const { baseUrl } = getApiConfig();
	return {
		uri: joinUrl(baseUrl, path),
		headers: await authHeadersOnce(),
	};
}

// Текст по абсолютному пути сервера (/api/...): субтитры нельзя гнать
// через apiFetch — он парсит JSON. baseUrl содержит /api, поэтому origin
// отрезаем, иначе получили бы /api/api/....
export async function fetchAuthedText(path: string): Promise<string> {
	const { baseUrl } = getApiConfig();
	const origin = baseUrl.replace(API_SUFFIX, "");
	const target = new URL(
		HTTP_URL_START.test(path)
			? path
			: `${origin}${path.startsWith("/") ? "" : "/"}${path}`,
	);
	// Bearer уходит только на свой сервер: абсолютный URL из ответа API
	// не должен уводить токен на чужой origin.
	if (target.origin !== new URL(origin).origin) {
		throw new Error("Cross-origin subtitle URL rejected");
	}
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), 15_000);
	try {
		const response = await fetch(target.toString(), {
			headers: await authHeadersOnce(),
			signal: controller.signal,
		});
		if (!response.ok) {
			throw new Error(`HTTP ${response.status}`);
		}
		return await response.text();
	} finally {
		clearTimeout(timer);
	}
}

// Ссылка на источник открывается только по http(s): javascript:, file:,
// data: и относительные пути не должны попасть в Linking.openURL.
// Хост обязателен, поэтому "https://" и пустая строка отсекаются.
const HTTP_URL_PATTERN = /^https?:\/\/[^\s/]+(?:[/?#]\S*)?$/i;

export function isHttpSourceUrl(value: string): boolean {
	return HTTP_URL_PATTERN.test(value.trim());
}

// Единственная точка сборки медиа-URL: id — числовой из схемы Media.
export function streamPath(id: number): string {
	return `/media/${id}/stream`;
}

export function thumbPath(id: number): string {
	return `/media/${id}/thumb`;
}

export function coverPath(id: number): string {
	return `/media/${id}/cover`;
}

// Обложка артиста кешируется по updated_at: после загрузки новой обложки
// прежний URL не должен оставаться в кэше expo-image.
export function artistCoverPath(id: number, updatedAt: string): string {
	return `/artists/${id}/cover?v=${encodeURIComponent(updatedAt)}`;
}

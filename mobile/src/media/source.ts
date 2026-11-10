import { getApiConfig } from "@flux/shared";

// Источник для expo-video/expo-audio/expo-image: абсолютный URL и заголовки
// авторизации. Тип структурный, поэтому импортировать сами библиотеки здесь
// не нужно — их source-объекты принимают ту же форму.
export interface AuthSource {
	uri: string;
	headers: Record<string, string>;
}

const TRAILING_SLASHES = /\/+$/;
const LEADING_SLASHES = /^\/+/;

// baseUrl приходит из настроек сервера и может быть с хвостовым слэшем,
// а путь — без ведущего. Склеиваем ровно одним слэшем, чтобы не получить
// `//media` (некоторые серверы и CDN трактуют такой путь иначе).
function joinUrl(baseUrl: string, path: string): string {
	const base = baseUrl.replace(TRAILING_SLASHES, "");
	const suffix = path.replace(LEADING_SLASHES, "");
	return `${base}/${suffix}`;
}

// Токен не кешируется: authHeaders() каждый раз читает SecureStore, иначе
// после refresh плеер продолжил бы ходить со старым access-токеном.
export async function authSource(path: string): Promise<AuthSource> {
	const { baseUrl, transport } = getApiConfig();
	return {
		uri: joinUrl(baseUrl, path),
		headers: await transport.authHeaders(),
	};
}

// expo-image/video/audio принимают одну и ту же форму { uri, headers };
// алиас нужен для читаемости вызовов у постеров и обложек.
export const imageSource = authSource;

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

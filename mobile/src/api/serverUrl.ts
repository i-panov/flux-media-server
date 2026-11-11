const HTTP_SCHEME = /^https?:\/\//i;
const ANY_SCHEME = /^([a-z][a-z0-9+.-]*):\/\//i;
const PRIVATE_10 = /^10\./;
const PRIVATE_192 = /^192\.168\./;
const PRIVATE_172 = /^172\.(1[6-9]|2\d|3[0-1])\./;

// Без схемы публичный адрес получает https, локальный — http.
// Иначе ввод «flux.example.com» уходил бы на http и не логинился,
// а «192.168.1.10:8080» — на https, где TLS обычно нет.
function defaultScheme(value: string): "http" | "https" {
	const host = value.split("/")[0]?.toLowerCase() ?? "";
	if (
		host === "localhost" ||
		host.startsWith("localhost:") ||
		host === "127.0.0.1" ||
		host.startsWith("127.") ||
		host === "[::1]" ||
		host.startsWith("[::1]:") ||
		host.endsWith(".local") ||
		PRIVATE_10.test(host) ||
		PRIVATE_192.test(host) ||
		PRIVATE_172.test(host)
	) {
		return "http";
	}
	return "https";
}

// Нормализует адрес сервера в baseUrl API. Идемпотентно добавляет
// ровно один /api, принимает адрес без схемы, режет хвостовые слэши,
// query/fragment/userinfo отбрасывает. Невалидный ввод — null.
export function normalizeServerUrl(value: string): string | null {
	let raw = value.trim();
	if (raw === "") {
		return null;
	}

	const anyScheme = raw.match(ANY_SCHEME);
	if (anyScheme !== null && !HTTP_SCHEME.test(raw)) {
		return null;
	}
	if (!HTTP_SCHEME.test(raw)) {
		raw = `${defaultScheme(raw)}://${raw}`;
	}

	let url: URL;
	try {
		url = new URL(raw);
	} catch {
		return null;
	}
	if (!url.hostname) {
		return null;
	}

	const segments = url.pathname.split("/").filter((part) => part !== "");
	if (segments.length === 0) {
		segments.push("api");
	} else if (segments[segments.length - 1]?.toLowerCase() === "api") {
		segments[segments.length - 1] = "api";
	} else {
		segments.push("api");
	}

	return `${url.protocol}//${url.host}/${segments.join("/")}`;
}

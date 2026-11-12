// Минимальный стенд бэкенда для интеграционного e2e-теста прокси.
// Проверяет пару Origin/Host ровно как checkSameOrigin и ведёт настоящие
// httpOnly-куки, чтобы прогнать вход через реальный Vite-прокси,
// а не через перехват page.route (он до прокси не достаёт).
import { createServer } from "node:http";

const PORT = Number(process.env.FAKE_BACKEND_PORT ?? "18080");

const issuedAccess = new Set();
const issuedRefresh = new Set();
let counter = 0;
const deviceCodes = new Map();

function sameOrigin(req) {
	const origin = req.headers.origin ?? "";
	if (origin === "") {
		return true;
	}
	let host = "";
	try {
		host = new URL(origin).host;
	} catch {
		return false;
	}
	if (host === "") {
		return false;
	}
	return host.toLowerCase() === String(req.headers.host ?? "").toLowerCase();
}

function parseCookies(req) {
	const result = {};
	for (const part of String(req.headers.cookie ?? "").split(";")) {
		const index = part.indexOf("=");
		if (index > 0) {
			result[part.slice(0, index).trim()] = part.slice(index + 1).trim();
		}
	}
	return result;
}

function isAuthed(req) {
	const cookies = parseCookies(req);
	return issuedAccess.has(cookies.flux_access ?? "");
}

function readBody(req) {
	return new Promise((resolve, reject) => {
		let data = "";
		req.on("data", (chunk) => {
			data += chunk;
		});
		req.on("end", () => resolve(data));
		req.on("error", reject);
	});
}

function json(res, status, body, cookies = []) {
	const headers = { "Content-Type": "application/json" };
	if (cookies.length > 0) {
		headers["Set-Cookie"] = cookies;
	}
	res.writeHead(status, headers);
	res.end(JSON.stringify(body));
}

function issuePair() {
	counter += 1;
	const access = `fake-access-${counter}`;
	const refresh = `fake-refresh-${counter}`;
	issuedAccess.add(access);
	issuedRefresh.add(refresh);
	return { access, refresh };
}

function sessionCookies(access, refresh) {
	return [
		`flux_access=${access}; Path=/; HttpOnly; SameSite=Lax`,
		`flux_refresh=${refresh}; Path=/api/auth; HttpOnly; SameSite=Lax`,
	];
}

const server = createServer(async (req, res) => {
	const url = new URL(req.url ?? "/", "http://127.0.0.1");

	if (req.method === "GET" && url.pathname === "/api/health") {
		json(res, 200, { status: "ok", version: "0.0.0-fake" });
		return;
	}

	if (req.method === "POST" && url.pathname === "/api/auth/request-code") {
		json(res, 200, { message: "ok", code: "123456" });
		return;
	}

	if (req.method === "POST" && url.pathname === "/api/auth/verify-code") {
		if (!sameOrigin(req)) {
			json(res, 403, { error: "Cross-origin request rejected" });
			return;
		}
		const body = JSON.parse(await readBody(req));
		if (body.code !== "123456") {
			json(res, 401, { error: "Invalid or expired code" });
			return;
		}
		const { access, refresh } = issuePair();
		json(
			res,
			200,
			{
				token: access,
				refresh_token: refresh,
				user: { id: 1, email: body.email, is_admin: false },
			},
			sessionCookies(access, refresh),
		);
		return;
	}

	if (req.method === "GET" && url.pathname === "/api/auth/me") {
		const cookies = parseCookies(req);
		if (!issuedAccess.has(cookies.flux_access ?? "")) {
			json(res, 401, { error: "Unauthorized" });
			return;
		}
		json(res, 200, { id: 1, email: "user@example.com", is_admin: false });
		return;
	}

	if (req.method === "POST" && url.pathname === "/api/auth/refresh") {
		if (!sameOrigin(req)) {
			json(res, 403, { error: "Cross-origin request rejected" });
			return;
		}
		const cookies = parseCookies(req);
		const oldRefresh = cookies.flux_refresh ?? "";
		if (!issuedRefresh.has(oldRefresh)) {
			json(res, 401, { error: "Invalid or expired refresh token" });
			return;
		}
		issuedRefresh.delete(oldRefresh);
		const { access, refresh } = issuePair();
		json(
			res,
			200,
			{ token: access, refresh_token: refresh },
			sessionCookies(access, refresh),
		);
		return;
	}

	if (req.method === "POST" && url.pathname === "/api/auth/logout") {
		json(res, 200, { message: "ok" }, [
			"flux_access=; Path=/; Max-Age=0",
			"flux_refresh=; Path=/api/auth; Max-Age=0",
		]);
		return;
	}

	if (req.method === "POST" && url.pathname === "/api/auth/device/code") {
		const userCode = "654321";
		const deviceCode = `fake-device-${counter + 1}`;
		deviceCodes.set(deviceCode, {
			userCode,
			deviceName: "Fake TV",
			platform: "web-tv",
			approved: false,
		});
		json(res, 200, {
			device_code: deviceCode,
			user_code: userCode,
			verification_uri: "http://127.0.0.1:5174/activate",
			verification_uri_complete: `http://127.0.0.1:5174/activate#code=${userCode}`,
			expires_in: 300,
			interval: 1,
		});
		return;
	}

	if (req.method === "POST" && url.pathname === "/api/auth/device/inspect") {
		if (!isAuthed(req)) {
			json(res, 401, { error: "Unauthorized" });
			return;
		}
		const body = JSON.parse(await readBody(req));
		const userCode = String(body.user_code ?? "").replace(/\D/g, "");
		const entry = [...deviceCodes.entries()].find(
			([, value]) => value.userCode === userCode,
		);
		if (entry === undefined) {
			json(res, 404, { error: "Code not found" });
			return;
		}
		json(res, 200, {
			device_name: entry[1].deviceName,
			platform: entry[1].platform,
			expires_at: new Date(Date.now() + 300_000).toISOString(),
			current: false,
		});
		return;
	}

	if (req.method === "POST" && url.pathname === "/api/auth/device/approve") {
		if (!isAuthed(req)) {
			json(res, 401, { error: "Unauthorized" });
			return;
		}
		const body = JSON.parse(await readBody(req));
		const userCode = String(body.user_code ?? "").replace(/\D/g, "");
		const entry = [...deviceCodes.entries()].find(
			([, value]) => value.userCode === userCode,
		);
		if (entry === undefined) {
			json(res, 404, { error: "Code not found" });
			return;
		}
		entry[1].approved = true;
		json(res, 200, {
			approved: true,
			device_name: entry[1].deviceName,
			platform: entry[1].platform,
		});
		return;
	}

	if (req.method === "POST" && url.pathname === "/api/auth/device/token") {
		const body = JSON.parse(await readBody(req));
		const entry = deviceCodes.get(String(body.device_code ?? ""));
		if (entry === undefined) {
			json(res, 400, { status: "invalid_grant" });
			return;
		}
		if (!entry.approved) {
			json(res, 200, { status: "pending", interval: 1 });
			return;
		}
		const { access, refresh } = issuePair();
		json(
			res,
			200,
			{
				status: "ok",
				token: access,
				refresh_token: refresh,
				user: { id: 1, email: "user@example.com", is_admin: false },
			},
			sessionCookies(access, refresh),
		);
		return;
	}

	json(res, 404, { error: "Not found" });
});

server.listen(PORT, "127.0.0.1");

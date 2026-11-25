import { cleanupOutdatedCaches, precacheAndRoute } from "workbox-precaching";

// В DOM-библиотеке нет типов ServiceWorker scope,
// объявляем только то, что использует этот файл.
interface ExtendableActivateEvent extends Event {
	waitUntil(promise: Promise<unknown>): void;
}

interface FluxSWGlobalScope {
	readonly __WB_MANIFEST: Parameters<typeof precacheAndRoute>[0];
	readonly location: { readonly origin: string };
	skipWaiting(): Promise<void>;
	readonly clients: { claim(): Promise<void> };
	addEventListener(
		type: "activate",
		listener: (event: ExtendableActivateEvent) => void,
	): void;
	addEventListener(
		type: "fetch",
		listener: (event: {
			readonly request: Request;
			respondWith(response: Promise<Response>): void;
		}) => void,
	): void;
}

declare const self: FluxSWGlobalScope;

const STATIC_ASSET_PATTERN =
	/\.(?:js|css|mjs|map|png|jpe?g|gif|svg|webp|ico|woff2?|ttf|otf|webmanifest|json|txt|xml)$/i;

cleanupOutdatedCaches();
// vite-plugin-pwa подставляет сюда манифест precache при сборке.
precacheAndRoute(self.__WB_MANIFEST);

// Offline-навигация: precached index.html отвечает только на "/" —
// deep link (/video/42) при перезагрузке без сети иначе уходит в сеть
// и падает. API не перехватываем: его ответы не SPA.
self.addEventListener("fetch", (event) => {
	if (event.request.mode !== "navigate") {
		return;
	}
	const url = new URL(event.request.url);
	if (url.origin !== self.location.origin || url.pathname.startsWith("/api/")) {
		return;
	}
	// Только SPA-маршруты: прямой заход на /icon-512.png или /favicon.svg
	// должен отдавать файл, а не оболочку приложения.
	if (STATIC_ASSET_PATTERN.test(url.pathname)) {
		return;
	}
	// Network-first: после деплоя вкладка не залипает на старом precached
	// index.html; при отсутствии сети отдаём оболочку из кеша.
	event.respondWith(
		fetch(event.request).catch(() =>
			caches
				.match("/index.html", { ignoreSearch: true })
				.then((cached) => cached ?? Promise.reject(new Error("offline"))),
		),
	);
});

// Активацию запускает пользователь через PwaUpdatePrompt (SKIP_WAITING).
(
	self as unknown as {
		addEventListener(
			type: "message",
			listener: (event: { data?: { type?: string } }) => void,
		): void;
	}
).addEventListener("message", (event) => {
	if (event.data?.type === "SKIP_WAITING") {
		void self.skipWaiting();
	}
});

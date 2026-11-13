import { cleanupOutdatedCaches, precacheAndRoute } from "workbox-precaching";

// В DOM-библиотеке нет типов ServiceWorker scope,
// объявляем только то, что использует этот файл.
interface ExtendableActivateEvent extends Event {
	waitUntil(promise: Promise<unknown>): void;
}

interface FluxSWGlobalScope {
	readonly __WB_MANIFEST: Parameters<typeof precacheAndRoute>[0];
	skipWaiting(): Promise<void>;
	readonly clients: { claim(): Promise<void> };
	addEventListener(
		type: "activate",
		listener: (event: ExtendableActivateEvent) => void,
	): void;
}

declare const self: FluxSWGlobalScope;

cleanupOutdatedCaches();
// vite-plugin-pwa подставляет сюда манифест precache при сборке.
precacheAndRoute(self.__WB_MANIFEST);

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

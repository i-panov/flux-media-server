import { configureApi, createWebTransport } from "@flux/shared";
import { RouterProvider } from "@tanstack/react-router";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { getRouter } from "./router";
import "./i18n";
import "./styles.css";

// Веб раздаётся Go-сервером с того же origin (см. server.web_dist), поэтому
// API и cookie-сессия first-party. Отдельный API-origin не поддерживаем:
// SameSite=Lax-куки кросс-сайт не отправляются, а медиа-ссылки относительные.
configureApi({
	baseUrl: "/api",
	transport: createWebTransport(),
});

const rootElement = document.getElementById("root");
if (rootElement === null) {
	throw new Error("Root element not found");
}

createRoot(rootElement).render(
	<StrictMode>
		<RouterProvider router={getRouter()} />
	</StrictMode>,
);

import { configureApi, createWebTransport } from "@flux/shared";
import { RouterProvider } from "@tanstack/react-router";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { getRouter } from "./router";
import "./i18n";
import "./styles.css";

// Base URL бэкенда из окружения сборки: отдельный деплой веба живёт не на
// same-origin. Дефолт shared (/api) — для раздачи с того же origin.
const rawBase = (import.meta.env.VITE_API_BASE?.trim() || "/api").replace(
	/\/+$/,
	"",
);
const crossOrigin =
	new URL(rawBase, window.location.origin).origin !== window.location.origin;
configureApi({
	baseUrl: rawBase,
	transport: createWebTransport({
		credentials: crossOrigin ? "include" : "same-origin",
	}),
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

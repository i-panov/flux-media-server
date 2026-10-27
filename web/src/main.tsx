import { RouterProvider } from "@tanstack/react-router";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { getRouter } from "./router";
import "./i18n";
import "./styles.css";

const rootElement = document.getElementById("root");
if (rootElement === null) {
	throw new Error("Root element not found");
}

createRoot(rootElement).render(
	<StrictMode>
		<RouterProvider router={getRouter()} />
	</StrictMode>,
);

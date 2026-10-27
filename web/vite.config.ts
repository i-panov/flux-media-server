import { readFileSync } from "node:fs";
import tailwindcss from "@tailwindcss/vite";
import { tanstackRouter } from "@tanstack/router-plugin/vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
import { configDefaults, defineConfig } from "vitest/config";

const pkg = JSON.parse(
	readFileSync(new URL("./package.json", import.meta.url), "utf8"),
) as { version: string };

// Бэкенд сверяет Origin с Host (защита от login CSRF), поэтому Host
// обязан остаться браузерным: changeOrigin переписал бы его на адрес
// target-а, и все cookie-эндпоинты отвечали бы 403.
const apiProxy = {
	target: process.env.VITE_API_PROXY ?? "http://localhost:8080",
	changeOrigin: false,
};

export default defineConfig({
	plugins: [
		tanstackRouter({ target: "react", autoCodeSplitting: true }),
		react(),
		tailwindcss(),
		VitePWA({
			strategies: "injectManifest",
			srcDir: "src",
			filename: "sw.ts",
			registerType: "autoUpdate",
			injectRegister: "auto",
			includeAssets: ["favicon.svg", "icon-192.png", "icon-512.png"],
			manifest: {
				id: "/",
				name: "Flux",
				short_name: "Flux",
				description: "Flux media server",
				start_url: "/",
				scope: "/",
				display: "standalone",
				theme_color: "#0b0b0f",
				background_color: "#0b0b0f",
				icons: [
					{
						src: "/icon-192.png",
						sizes: "192x192",
						type: "image/png",
						purpose: "any",
					},
					{
						src: "/icon-512.png",
						sizes: "512x512",
						type: "image/png",
						purpose: "any",
					},
				],
			},
			injectManifest: {
				globPatterns: ["**/*.{js,css,html,svg,png,ico,woff2}"],
			},
			devOptions: {
				enabled: false,
			},
		}),
	],
	define: {
		__APP_VERSION__: JSON.stringify(pkg.version),
	},
	server: {
		proxy: {
			"/api": apiProxy,
		},
	},
	preview: {
		proxy: {
			"/api": apiProxy,
		},
	},
	test: {
		environment: "jsdom",
		globals: true,
		setupFiles: ["./vitest.setup.ts"],
		exclude: [...configDefaults.exclude, "e2e/**"],
		coverage: {
			provider: "v8",
			reporter: ["text", "html"],
			reportsDirectory: "coverage",
			include: ["src/**"],
			exclude: ["src/routeTree.gen.ts", "src/sw.ts", "src/main.tsx"],
		},
	},
});

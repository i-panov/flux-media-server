import { defineConfig, devices } from "@playwright/test";

// Запускается через `npm run test:e2e:real`: стенд (Docker media-loader,
// Redis, настоящий backend и Vite) поднимается shell-раннером.
export default defineConfig({
	testDir: "./e2e",
	testMatch: "**/real/*.spec.ts",
	fullyParallel: false,
	retries: 0,
	timeout: 180_000,
	reporter: "list",
	use: {
		baseURL: "http://127.0.0.1:5174",
		locale: "ru-RU",
	},
	projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});

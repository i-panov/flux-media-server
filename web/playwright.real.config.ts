import { defineConfig, devices } from "@playwright/test";

// Запускается через `npm run test:e2e:real`: стенд (Docker media-loader,
// Redis, настоящий backend и Vite) поднимается shell-раннером.
export default defineConfig({
	testDir: "./e2e",
	testMatch: "**/real/*.spec.ts",
	fullyParallel: false,
	// Один воркер: тесты делят реальный media-loader, кэш источника и
	// лимитер OTP — параллельный запуск даёт ложные падения.
	workers: 1,
	retries: 0,
	timeout: 180_000,
	reporter: "list",
	use: {
		baseURL: process.env.FLUX_E2E_BASE_URL ?? "http://127.0.0.1:5176",
		locale: "ru-RU",
	},
	projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});

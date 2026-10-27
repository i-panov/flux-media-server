import { defineConfig, devices } from "@playwright/test";

// Отдельный конфиг для сквозного proxy-теста: ему нужен свой Vite
// на отдельном порту и гарантированно свежие серверы — reuse отключён,
// иначе можно подхватить чужой dev без VITE_API_PROXY и тест пойдёт
// мимо fake-backend.
const vitePort = 5174;
const fakeBackendPort = 18080;

export default defineConfig({
	testDir: "./e2e",
	testMatch: "**/proxy-*.spec.ts",
	fullyParallel: true,
	forbidOnly: Boolean(process.env.CI),
	retries: process.env.CI ? 2 : 0,
	reporter: "list",
	use: {
		baseURL: `http://127.0.0.1:${vitePort}`,
		locale: "ru-RU",
		trace: "on-first-retry",
	},
	projects: [
		{
			name: "chromium",
			use: { ...devices["Desktop Chrome"] },
		},
	],
	webServer: [
		{
			command: `npm run dev -- --host 127.0.0.1 --port ${vitePort}`,
			url: `http://127.0.0.1:${vitePort}`,
			reuseExistingServer: false,
			timeout: 120_000,
			env: {
				VITE_API_PROXY: `http://127.0.0.1:${fakeBackendPort}`,
			},
		},
		{
			command: "node ./e2e/fake-backend.mjs",
			url: `http://127.0.0.1:${fakeBackendPort}/api/health`,
			reuseExistingServer: false,
			timeout: 30_000,
			env: {
				FAKE_BACKEND_PORT: String(fakeBackendPort),
			},
		},
	],
});

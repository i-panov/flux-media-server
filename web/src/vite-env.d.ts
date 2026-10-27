/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />

interface ImportMetaEnv {
	readonly VITE_API_BASE?: string;
}

declare const __APP_VERSION__: string;

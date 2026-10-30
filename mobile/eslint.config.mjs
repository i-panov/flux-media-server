// @ts-check

import { defineConfig, globalIgnores } from "eslint/config";
// flat.js напрямую: пакет кладёт рядом файл flat.js и каталог flat/,
// поэтому беспостфиксный "./flat" не резолвится ESM-импортом (ERR_UNSUPPORTED_DIR_IMPORT).
import expo from "eslint-config-expo/flat.js";
import sonarjs from "eslint-plugin-sonarjs";

export default defineConfig([
	globalIgnores([
		"**/node_modules/**",
		"**/dist/**",
		"**/.expo/**",
		"android/**",
		"ios/**",
	]),
	...expo,
	{
		files: ["**/*.{ts,tsx}"],
		plugins: {
			sonarjs: sonarjs.configs.recommended.plugins.sonarjs,
		},
		rules: {
			"sonarjs/no-identical-functions": "error",
			"sonarjs/no-duplicate-string": "error",
			"max-lines": ["error", { max: 500, skipBlankLines: true, skipComments: true }],
			"max-lines-per-function": ["error", { max: 200, skipBlankLines: true, skipComments: true }],
			"max-statements": ["error", 65],
			complexity: ["error", 30],
		},
	},
]);

// @ts-check

import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import globals from "globals";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import sonarjs from "eslint-plugin-sonarjs";
import tseslint from "typescript-eslint";

export default defineConfig([
	globalIgnores([
		"**/node_modules/**",
		"**/dist/**",
		"**/dev-dist/**",
		"**/routeTree.gen.ts",
		"**/coverage/**",
		"**/playwright-report/**",
		"**/test-results/**",
	]),

	// Plain JS/ESM files (postcss.config.mjs): core rules only.
	js.configs.recommended,

	{
		files: ["**/*.{ts,tsx}"],
		extends: [
			tseslint.configs.recommendedTypeChecked,
			react.configs.flat.recommended,
			react.configs.flat["jsx-runtime"],
			reactHooks.configs.flat.recommended,
		],
		languageOptions: {
			parserOptions: {
				projectService: true,
				tsconfigRootDir: import.meta.dirname,
			},
			globals: globals.browser,
		},
		plugins: {
			react,
			"react-hooks": reactHooks,
			sonarjs: sonarjs.configs.recommended.plugins.sonarjs,
		},
		settings: {
			react: {
				version: "detect",
			},
		},
		rules: {
			// TypeScript covers prop validation statically; runtime prop-types
			// checks add noise without value here.
			"react/prop-types": "off",
			// "_" prefixed bindings are the discard convention.
			"@typescript-eslint/no-unused-vars": [
				"error",
				{
					argsIgnorePattern: "^_",
					varsIgnorePattern: "^_",
					ignoreRestSiblings: true,
				},
			],
			// Flags the idiomatic "reset derived state" pattern; keep it as a
			// warning so new code follows the recommended approach without
			// blocking existing implementations.
			"react-hooks/set-state-in-effect": "warn",
			"sonarjs/no-identical-functions": "error",
			"sonarjs/no-duplicate-string": "error",
			"max-lines": ["error", { max: 500, skipBlankLines: true, skipComments: true }],
			"max-lines-per-function": ["error", { max: 200, skipBlankLines: true, skipComments: true }],
			"max-statements": ["error", 65],
			complexity: ["error", 30],
		},
	},

	// Test files repeat fixture strings by design.
	{
		files: [
			"**/*.{test,spec}.{ts,tsx}",
			"**/*.e2e.ts",
			"**/__tests__/**/*.{ts,tsx}",
		],
		rules: {
			"sonarjs/no-duplicate-string": "off",
			"max-lines-per-function": "off",
		},
	},

	{
		files: ["src/sw.ts"],
		languageOptions: {
			globals: globals.serviceworker,
		},
	},

	// Node-side config/setup files are not part of the browser bundle.
	{
		files: [
			"vite.config.ts",
			"vitest.setup.ts",
			"postcss.config.mjs",
			"playwright.config.ts",
			"e2e/**/*.ts",
		],
		languageOptions: {
			globals: globals.node,
		},
	},
]);

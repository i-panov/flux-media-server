// @ts-check

import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import globals from "globals";
import sonarjs from "eslint-plugin-sonarjs";
import tseslint from "typescript-eslint";

export default defineConfig([
	globalIgnores(["**/node_modules/**", "**/dist/**", "**/coverage/**"]),
	js.configs.recommended,
	{
		files: ["**/*.ts"],
		extends: [tseslint.configs.recommendedTypeChecked],
		languageOptions: {
			parserOptions: {
				projectService: true,
				tsconfigRootDir: import.meta.dirname,
			},
			globals: globals.node,
		},
		plugins: {
			sonarjs: sonarjs.configs.recommended.plugins.sonarjs,
		},
		rules: {
			"@typescript-eslint/no-unused-vars": [
				"error",
				{
					argsIgnorePattern: "^_",
					varsIgnorePattern: "^_",
					ignoreRestSiblings: true,
				},
			],
			"sonarjs/no-identical-functions": "error",
			"sonarjs/no-duplicate-string": "error",
			"max-lines": ["error", { max: 500, skipBlankLines: true, skipComments: true }],
			"max-lines-per-function": ["error", { max: 200, skipBlankLines: true, skipComments: true }],
			"max-statements": ["error", 65],
			complexity: ["error", 30],
		},
	},
	{
		files: ["**/*.{test,spec}.ts", "**/__tests__/**/*.ts"],
		rules: {
			"sonarjs/no-duplicate-string": "off",
			"max-lines-per-function": "off",
		},
	},
]);

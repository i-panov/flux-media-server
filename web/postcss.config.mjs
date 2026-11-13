import postcssPresetMantine from "postcss-preset-mantine";
import postcssSimpleVars from "postcss-simple-vars";

// Chromium 76 (Tizen 6.5) не понимает @layer и выбрасывает utilities.
// Разворачиваем слои в обычный каскад; порядок сохраняется как в файле.
const flattenLayers = {
	postcssPlugin: "flatten-layers",
	Once(root) {
		root.walkAtRules("layer", (atRule) => {
			if (atRule.nodes) {
				atRule.replaceWith(atRule.nodes);
			} else {
				atRule.remove();
			}
		});
	},
};

export default {
	plugins: [
		flattenLayers,
		postcssPresetMantine(),
		postcssSimpleVars({
			variables: {
				"mantine-breakpoint-xs": "36em",
				"mantine-breakpoint-sm": "48em",
				"mantine-breakpoint-md": "62em",
				"mantine-breakpoint-lg": "75em",
				"mantine-breakpoint-xl": "88em",
			},
		}),
	],
};

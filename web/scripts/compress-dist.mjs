/* global URL, console */
import { brotliCompressSync, gzipSync } from "node:zlib";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { extname, join } from "node:path";

const root = new URL("../dist/", import.meta.url).pathname;
const textExtensions = new Set([
	".js",
	".mjs",
	".css",
	".html",
	".svg",
	".json",
	".webmanifest",
	".txt",
	".xml",
]);
const minimumBytes = 1024;

function walk(dir) {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const path = join(dir, entry.name);
		if (entry.isDirectory()) {
			walk(path);
		} else if (entry.isFile() && textExtensions.has(extname(entry.name))) {
			const source = readFileSync(path);
			if (source.length < minimumBytes) continue;
			const brotli = brotliCompressSync(source);
			const gzip = gzipSync(source, { level: 9 });
			if (brotli.length < source.length) {
				writeFileSync(`${path}.br`, brotli);
			}
			if (gzip.length < source.length) {
				writeFileSync(`${path}.gz`, gzip);
			}
			console.log(
				`compressed ${path.slice(root.length)}: ${source.length} -> br ${brotli.length}, gz ${gzip.length}`,
			);
		}
	}
}

walk(root);

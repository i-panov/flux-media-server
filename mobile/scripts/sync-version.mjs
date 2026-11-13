// Синхронизирует app.json с mobile/package.json и mobile/version-code.
// versionCode хранится отдельным файлом, чтобы проверка ловила и дрейф
// версии, и дрейф кода сборки. `--check` ничего не пишет и падает при
// рассинхроне (для CI).
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const app = JSON.parse(readFileSync(join(root, "app.json"), "utf8"));
const codePath = join(root, "version-code");
const storedCode = Number(readFileSync(codePath, "utf8").trim());
const appCode = Number(app.expo.android?.versionCode ?? 0);
const iosCode = String(app.expo.ios?.buildNumber ?? "0");
const check = process.argv.includes("--check");

if (!Number.isInteger(storedCode) || storedCode <= 0) {
	console.error("version-code должен быть положительным целым");
	process.exit(1);
}

const versionDrift = app.expo.version !== pkg.version;
const codeDrift = appCode !== storedCode;
const iosDrift = iosCode !== String(storedCode);

if (check) {
	if (versionDrift || codeDrift || iosDrift) {
		console.error(
			`mobile version drift: package=${pkg.version}, app=${app.expo.version}, code=${appCode}, ios=${iosCode}, stored=${storedCode}`,
		);
		process.exit(1);
	}
	console.log(`mobile version ${pkg.version}, versionCode ${storedCode} in sync`);
} else if (versionDrift) {
	const next = Math.max(storedCode, appCode) + 1;
	app.expo.version = pkg.version;
	app.expo.android = { ...app.expo.android, versionCode: next };
	app.expo.ios = { ...app.expo.ios, buildNumber: String(next) };
	writeFileSync(join(root, "app.json"), `${JSON.stringify(app, null, 2)}\n`);
	writeFileSync(codePath, `${next}\n`);
	console.log(`mobile version ${pkg.version}, versionCode ${next}`);
} else if (codeDrift) {
	app.expo.android = { ...app.expo.android, versionCode: storedCode };
	app.expo.ios = { ...app.expo.ios, buildNumber: String(storedCode) };
	writeFileSync(join(root, "app.json"), `${JSON.stringify(app, null, 2)}\n`);
	console.log(`mobile versionCode restored to ${storedCode}`);
} else {
	console.log(`mobile version ${pkg.version} already in sync`);
}

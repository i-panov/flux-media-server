const { withAppBuildGradle } = require("@expo/config-plugins");

// Release-подпись не должна молча использовать debug.keystore. Если заданы
// FLUX_KEYSTORE_PATH/ALIAS/PASSWORDS — собираем release с ним, иначе
// оставляем debug для dogfood и явно предупреждаем в логе Gradle.
module.exports = function withReleaseSigning(config) {
	return withAppBuildGradle(config, (cfg) => {
		let contents = cfg.modResults.contents;
		if (!contents.includes("fluxReleaseSigning")) {
			contents = contents.replace(
				"signingConfigs {",
				`signingConfigs {
        // fluxReleaseSigning: реальный ключ только из окружения.
        if (process.env.FLUX_KEYSTORE_PATH) {
            release {
                storeFile file(process.env.FLUX_KEYSTORE_PATH)
                storePassword System.getenv("FLUX_KEYSTORE_PASSWORD")
                keyAlias System.getenv("FLUX_KEY_ALIAS")
                keyPassword System.getenv("FLUX_KEY_PASSWORD")
            }
        }`,
			);
		}
		if (process.env.FLUX_KEYSTORE_PATH) {
			for (const key of [
				"FLUX_KEYSTORE_PASSWORD",
				"FLUX_KEY_ALIAS",
				"FLUX_KEY_PASSWORD",
			]) {
				if (!process.env[key]) {
					throw new Error(`withReleaseSigning: ${key} is required with FLUX_KEYSTORE_PATH`);
				}
			}
		}
		const releaseRe = /(\n\s*release\s*\{[\s\S]*?)signingConfig signingConfigs\.debug([\s\S]*?\n\s*\})/;
		if (!releaseRe.test(contents)) {
			throw new Error("withReleaseSigning: release buildType block not found");
		}
		contents = contents.replace(
			releaseRe,
			`$1signingConfig process.env.FLUX_KEYSTORE_PATH ? signingConfigs.release : signingConfigs.debug
            if (!process.env.FLUX_KEYSTORE_PATH) {
                logger.warn("fluxReleaseSigning: FLUX_KEYSTORE_PATH is not set; release is signed with debug.keystore")
            }$2`,
		);
		if (!contents.includes('process.env.FLUX_KEYSTORE_PATH ? signingConfigs.release')) {
			throw new Error("withReleaseSigning: failed to replace release signingConfig");
		}
		cfg.modResults.contents = contents;
		return cfg;
	});
};

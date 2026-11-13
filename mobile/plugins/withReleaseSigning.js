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
        if (System.getenv("FLUX_KEYSTORE_PATH")) {
            release {
                storeFile file(System.getenv("FLUX_KEYSTORE_PATH"))
                storePassword System.getenv("FLUX_KEYSTORE_PASSWORD")
                keyAlias System.getenv("FLUX_KEY_ALIAS")
                keyPassword System.getenv("FLUX_KEY_PASSWORD")
            }
        }`,
			);
		}
		contents = contents.replace(
			"signingConfig signingConfigs.debug\n            def enableShrinkResources",
			`signingConfig System.getenv("FLUX_KEYSTORE_PATH") ? signingConfigs.release : signingConfigs.debug
            if (!System.getenv("FLUX_KEYSTORE_PATH")) {
                logger.warn("fluxReleaseSigning: FLUX_KEYSTORE_PATH is not set; release is signed with debug.keystore")
            }
            def enableShrinkResources`,
		);
		cfg.modResults.contents = contents;
		return cfg;
	});
};

const { withAndroidManifest } = require("@expo/config-plugins");

// Self-hosted Flux часто живёт на LAN по http://: Expo не применяет
// android.usesCleartextTraffic из app.json, поэтому правим манифест явно.
module.exports = function withCleartextTraffic(config) {
	return withAndroidManifest(config, (config) => {
		const application = config.modResults.manifest.application?.[0];
		if (application) {
			application.$["android:usesCleartextTraffic"] = "true";
		}
		return config;
	});
};

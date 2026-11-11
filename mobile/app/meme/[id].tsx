import { Image } from "expo-image";
import { router, useLocalSearchParams } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useMedia } from "../../src/api/media";
import { AuthGate } from "../../src/components/AuthGate";
import { ErrorState } from "../../src/components/ErrorState";
import { t, useLanguage } from "../../src/i18n";
import { thumbPath } from "../../src/media/source";
import { useAuthImageSource } from "../../src/media/useAuthImageSource";
import { useTheme } from "../../src/theme/ThemeProvider";

function close(): void {
	if (router.canGoBack()) router.back();
	else router.replace("/memes");
}

function MemeContent() {
	useLanguage();
	const { colors } = useTheme();
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const raw = Array.isArray(params.id) ? params.id[0] : params.id;
	const id = raw === undefined ? Number.NaN : Number(raw);
	const valid = Number.isInteger(id) && id > 0;
	const media = useMedia(valid ? id : 0, valid);
	const source = useAuthImageSource(valid ? thumbPath(id) : null);

	return (
		<View style={[styles.screen, { backgroundColor: colors.playerChrome }]}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={close}
				testID="meme-back"
				style={styles.back}
			>
				<Text style={styles.backText}>‹ {t("common.back")}</Text>
			</Pressable>
			{!valid || media.isError ? (
				<ErrorState onRetry={() => void media.refetch()} />
			) : media.data === undefined ? (
				<Text style={styles.loading}>{t("common.loading")}</Text>
			) : (
				<>
					<Image
						source={source}
						style={styles.image}
						contentFit="contain"
						accessibilityLabel={media.data.title}
					/>
					<Text style={styles.title} numberOfLines={2}>
						{media.data.title}
					</Text>
				</>
			)}
		</View>
	);
}

export default function MemeScreen() {
	return (
		<AuthGate>
			<MemeContent />
		</AuthGate>
	);
}

const styles = StyleSheet.create({
	screen: { flex: 1, padding: 16 },
	back: { minHeight: 44, justifyContent: "center" },
	backText: { color: "#fff", fontSize: 16, fontWeight: "600" },
	image: { flex: 1, width: "100%" },
	title: { color: "#fff", fontSize: 18, fontWeight: "600", paddingVertical: 8 },
	loading: { color: "#fff", textAlign: "center", marginTop: 40 },
});

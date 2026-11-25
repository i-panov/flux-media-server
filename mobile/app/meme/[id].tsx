import Ionicons from "@expo/vector-icons/Ionicons";
import { Image } from "expo-image";
import { router, useLocalSearchParams } from "expo-router";
import { Alert, Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import {
	useFavoriteImageIds,
	useToggleImageFavorite,
} from "../../src/api/favorites";
import { useMedia } from "../../src/api/media";
import { AuthGate } from "../../src/components/AuthGate";
import { DownloadButton } from "../../src/components/DownloadButton";
import { ErrorState } from "../../src/components/ErrorState";
import { t, useLanguage } from "../../src/i18n";
import { streamPath } from "../../src/media/source";
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
	const source = useAuthImageSource(valid ? streamPath(id) : null);
	const favorites = useFavoriteImageIds();
	const toggleFavorite = useToggleImageFavorite();
	const favorite = valid && (favorites.data?.has(id) ?? false);
	const favoriteBusy = favorites.isFetching || toggleFavorite.isPending;

	return (
		<SafeAreaView
			edges={["top", "bottom"]}
			style={[styles.screen, { backgroundColor: colors.playerChrome }]}
		>
			<View style={styles.topBar}>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("common.back")}
					onPress={close}
					testID="meme-back"
					style={styles.back}
				>
					<Text style={styles.backText}>‹ {t("common.back")}</Text>
				</Pressable>
				{media.data !== undefined && (
					<View style={styles.actions}>
						<Pressable
							accessibilityRole="button"
							accessibilityLabel={
								favorite ? t("media.unfavorite") : t("media.favorite")
							}
							accessibilityState={{
								selected: favorite,
								disabled: favoriteBusy,
							}}
							disabled={favoriteBusy}
							testID="meme-favorite"
							onPress={() => {
								toggleFavorite.mutate(
									{ mediaId: id, favorite, media: media.data },
									{ onError: () => Alert.alert(t("video.favoriteError")) },
								);
							}}
							style={styles.iconButton}
						>
							<Ionicons
								name={favorite ? "heart" : "heart-outline"}
								size={26}
								color={favorite ? "#e5484d" : "#fff"}
							/>
						</Pressable>
						{media.data.type !== "image" && (
							<DownloadButton media={media.data} testID="meme-download" />
						)}
					</View>
				)}
			</View>
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
		</SafeAreaView>
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
	topBar: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		minHeight: 44,
	},
	actions: { flexDirection: "row", alignItems: "center", gap: 8 },
	iconButton: {
		minHeight: 44,
		minWidth: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	back: { minHeight: 44, justifyContent: "center" },
	backText: { color: "#fff", fontSize: 16, fontWeight: "600" },
	image: { flex: 1, width: "100%" },
	title: { color: "#fff", fontSize: 18, fontWeight: "600", paddingVertical: 8 },
	loading: { color: "#fff", textAlign: "center", marginTop: 40 },
});

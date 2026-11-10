import Ionicons from "@expo/vector-icons/Ionicons";
import type { Media } from "@flux/shared";
import { Image } from "expo-image";
import { useEffect, useState } from "react";
import { StyleSheet, View } from "react-native";
import { coverPath, imageSource, thumbPath } from "../media/source";
import { useTheme } from "../theme/ThemeProvider";

// Постер берёт авторизованный source из imageSource: media.cover_url уже
// содержит /api и без заголовков отдал бы 401. Cover используем, только
// если он реально есть, иначе — thumbnail.
export function VideoPoster({ media }: { media: Media }) {
	const { colors } = useTheme();
	// Cover есть не у всех видео, а файл cover мог быть удалён отдельно:
	// при ошибке загрузки откатываемся на thumbnail.
	const thumbnail = thumbPath(media.id);
	const [path, setPath] = useState(
		media.cover_url === "" ? thumbnail : coverPath(media.id),
	);
	const [loaded, setLoaded] = useState<{
		path: string;
		source: Awaited<ReturnType<typeof imageSource>>;
	} | null>(null);
	// Оба варианта (cover и thumbnail) могут отсутствовать/биться: тогда
	// показываем заглушку, а не пустую surface-плашку с broken image.
	const [failed, setFailed] = useState(false);

	useEffect(() => {
		let active = true;
		imageSource(path).then(
			(next) => {
				if (active) {
					setLoaded({ path, source: next });
				}
			},
			() => {
				if (active) {
					setLoaded(null);
				}
			},
		);
		return () => {
			active = false;
		};
	}, [path]);

	// Path сменился (cover -> thumbnail), а loaded ещё от старого: показываем
	// placeholder, а не устаревшую картинку, пока грузится новый source.
	const source = loaded !== null && loaded.path === path ? loaded.source : null;

	return (
		<View
			testID="video-player-poster"
			style={[
				StyleSheet.absoluteFill,
				styles.poster,
				{ backgroundColor: colors.surfaceMuted },
			]}
		>
			{source === null || failed ? (
				<View style={styles.placeholder}>
					<Ionicons
						name="videocam-outline"
						size={40}
						color={colors.textMuted}
					/>
				</View>
			) : (
				<Image
					source={source}
					style={StyleSheet.absoluteFill}
					contentFit="cover"
					transition={150}
					accessibilityIgnoresInvertColors
					onError={() => {
						if (path !== thumbnail) {
							setFailed(false);
							setPath(thumbnail);
							return;
						}
						setFailed(true);
					}}
				/>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	poster: { overflow: "hidden" },
	placeholder: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
	},
});

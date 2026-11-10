import Ionicons from "@expo/vector-icons/Ionicons";
import { Image } from "expo-image";
import { useEffect, useState } from "react";
import { StyleSheet, View } from "react-native";
import type { ArtistEntry } from "../api/metadata";
import { t, useLanguage } from "../i18n";
import { artistCoverPath, imageSource } from "../media/source";
import { useTheme } from "../theme/ThemeProvider";

interface ArtistCoverProps {
	artist: Pick<ArtistEntry, "id" | "name" | "has_cover" | "updated_at">;
	size: number;
	testID?: string;
	/** В строке списка обложка декоративна: имя уже озвучивает строка. */
	decorative?: boolean;
}

// Обложка артиста отдаётся только с Bearer-токеном (как и медиа), поэтому
// source собирается через authSource. Нет обложки/ошибка — иконка.
export function ArtistCover({
	artist,
	size,
	testID = `artist-cover-${artist.id}`,
	decorative = false,
}: ArtistCoverProps) {
	useLanguage();
	const { colors, radii } = useTheme();
	const path = artist.has_cover
		? artistCoverPath(artist.id, artist.updated_at)
		: null;
	const [loaded, setLoaded] = useState<{
		path: string;
		source: Awaited<ReturnType<typeof imageSource>>;
	} | null>(null);
	const [failedPath, setFailedPath] = useState<string | null>(null);

	useEffect(() => {
		if (path === null) {
			return;
		}
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

	const source =
		path !== null && loaded !== null && loaded.path === path
			? loaded.source
			: null;
	const failed = path !== null && failedPath === path;

	return (
		<View
			testID={testID}
			accessible={!decorative}
			accessibilityLabel={
				decorative ? undefined : `${t("artists.cover")}: ${artist.name}`
			}
			accessibilityElementsHidden={decorative}
			importantForAccessibility={decorative ? "no-hide-descendants" : "auto"}
			style={[
				styles.cover,
				{
					width: size,
					height: size,
					borderRadius: radii.md,
					backgroundColor: colors.surfaceMuted,
				},
			]}
		>
			{source === null || failed ? (
				<View style={styles.placeholder}>
					<Ionicons
						name="person-outline"
						size={Math.max(18, Math.round(size / 3))}
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
					onError={() => setFailedPath(path)}
				/>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	cover: { overflow: "hidden" },
	placeholder: {
		flex: 1,
		alignItems: "center",
		justifyContent: "center",
	},
});

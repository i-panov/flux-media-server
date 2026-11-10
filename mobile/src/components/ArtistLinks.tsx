import { router } from "expo-router";
import { Fragment } from "react";
import {
	Pressable,
	type StyleProp,
	StyleSheet,
	Text,
	type TextStyle,
	View,
} from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

type ArtistLink = { id: number; name: string };

interface ArtistLinksProps {
	artists: readonly ArtistLink[];
	emptyLabel: string;
	style?: StyleProp<TextStyle>;
	testID?: string;
	align?: "start" | "center";
}

// Имена артистов в плеере и тексте песни — ссылки на /artists/[id].
// Каждое имя тапается отдельно: у трека бывает несколько исполнителей.
export function ArtistLinks({
	artists,
	emptyLabel,
	style,
	testID,
	align = "start",
}: ArtistLinksProps) {
	useLanguage();
	const { colors } = useTheme();
	const visible = artists.filter((artist) => artist.name.trim() !== "");

	if (visible.length === 0) {
		return (
			<Text
				testID={testID}
				style={[styles.text, { color: colors.textMuted }, style]}
			>
				{emptyLabel}
			</Text>
		);
	}

	return (
		<View
			testID={testID}
			style={[styles.row, align === "center" && styles.center]}
		>
			{visible.map((artist, index) => (
				<Fragment key={artist.id}>
					{index > 0 && (
						<Text style={[styles.text, { color: colors.textMuted }, style]}>
							{", "}
						</Text>
					)}
					<Pressable
						accessibilityRole="link"
						accessibilityLabel={artist.name}
						accessibilityHint={t("artists.openArtist")}
						onPress={() => router.push(`/artists/${artist.id}`)}
						testID={`artist-link-${artist.id}`}
						hitSlop={8}
						style={({ pressed }) => pressed && styles.pressed}
					>
						<Text style={[styles.text, { color: colors.textMuted }, style]}>
							{artist.name}
						</Text>
					</Pressable>
				</Fragment>
			))}
		</View>
	);
}

const styles = StyleSheet.create({
	row: {
		flexDirection: "row",
		flexWrap: "wrap",
		alignItems: "center",
	},
	center: { justifyContent: "center" },
	text: { fontSize: 14 },
	pressed: { opacity: 0.7 },
});

import Ionicons from "@expo/vector-icons/Ionicons";
import { Image } from "expo-image";
import { Pressable, Text, View } from "react-native";
import { useTheme } from "../theme/ThemeProvider";

export function CatalogCard({
	id,
	title,
	coverURL,
	icon,
	onPress,
	testID,
}: {
	id: number;
	title: string;
	coverURL: string;
	icon: "tv" | "film";
	onPress: () => void;
	testID: string;
}) {
	const { colors, radii, spacing } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={title}
			onPress={onPress}
			testID={testID}
			style={{ width: 160, gap: spacing.xs }}
		>
			<View
				style={{
					aspectRatio: 16 / 9,
					borderRadius: radii.md,
					overflow: "hidden",
					backgroundColor: colors.surface,
					alignItems: "center",
					justifyContent: "center",
				}}
			>
				{coverURL ? (
					<Image
						source={{ uri: coverURL }}
						style={{ width: "100%", height: "100%" }}
						contentFit="cover"
					/>
				) : (
					<Ionicons name={icon} size={30} color={colors.textMuted} />
				)}
			</View>
			<Text numberOfLines={2} style={{ color: colors.text, fontWeight: "600" }}>
				{title || `#${id}`}
			</Text>
		</Pressable>
	);
}

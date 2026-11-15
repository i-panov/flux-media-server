import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import { Pressable, Text, View } from "react-native";
import { t } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

export function CatalogHeader({
	title,
	onBack,
}: {
	title: string;
	onBack: () => void;
}) {
	const { colors, spacing } = useTheme();
	return (
		<View
			style={{
				flexDirection: "row",
				alignItems: "center",
				gap: spacing.sm,
				paddingHorizontal: spacing.md,
				paddingVertical: spacing.sm,
			}}
		>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={() => {
					if (router.canGoBack()) router.back();
					else onBack();
				}}
				hitSlop={8}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<Text
				numberOfLines={1}
				style={{ flex: 1, color: colors.text, fontSize: 20, fontWeight: "700" }}
			>
				{title}
			</Text>
		</View>
	);
}

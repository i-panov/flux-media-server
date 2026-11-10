import Ionicons from "@expo/vector-icons/Ionicons";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface CollectionBackHeaderProps {
	title: string;
	subtitle?: string;
	onBack: () => void;
}

export function CollectionBackHeader({
	title,
	subtitle,
	onBack,
}: CollectionBackHeaderProps) {
	useLanguage();
	const { colors, spacing } = useTheme();
	return (
		<View style={[styles.header, { gap: spacing.sm }]}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={onBack}
				testID="collection-detail-back"
				hitSlop={8}
				style={({ pressed }) => [
					styles.headerButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<View style={styles.headerInfo}>
				<Text
					numberOfLines={1}
					testID="collection-detail-title"
					style={[styles.headerTitle, { color: colors.text }]}
				>
					{title}
				</Text>
				{subtitle !== undefined && (
					<Text
						numberOfLines={1}
						style={[styles.headerSubtitle, { color: colors.textMuted }]}
					>
						{subtitle}
					</Text>
				)}
			</View>
			<View style={styles.headerButton} />
		</View>
	);
}

const styles = StyleSheet.create({
	header: { flexDirection: "row", alignItems: "center" },
	headerButton: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	headerInfo: { flex: 1 },
	headerTitle: { fontSize: 18, fontWeight: "700" },
	headerSubtitle: { fontSize: 12 },
	pressed: { opacity: 0.7 },
});

import Ionicons from "@expo/vector-icons/Ionicons";
import type { Collection } from "@flux/shared";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface CollectionBreadcrumbsProps {
	crumbs: readonly Collection[];
	onPress: (collectionId: number) => void;
}

// Путь до текущей коллекции. Для корня дублировать нечего — заголовок
// экрана уже показывает имя, поэтому компонент молчит при одном элементе.
export function CollectionBreadcrumbs({
	crumbs,
	onPress,
}: CollectionBreadcrumbsProps) {
	useLanguage();
	const { colors, spacing } = useTheme();
	if (crumbs.length <= 1) {
		return null;
	}
	return (
		<ScrollView
			horizontal
			showsHorizontalScrollIndicator={false}
			style={styles.fill}
			contentContainerStyle={[styles.content, { gap: spacing.xs }]}
			testID="collection-breadcrumbs"
		>
			{crumbs.map((crumb, index) => {
				const current = index === crumbs.length - 1;
				return (
					<View key={crumb.id} style={styles.crumbGroup}>
						<Pressable
							accessibilityRole={current ? "text" : "button"}
							accessibilityLabel={crumb.name}
							disabled={current}
							onPress={() => onPress(crumb.id)}
							testID={`collection-breadcrumb-${crumb.id}`}
							style={({ pressed }) => [styles.crumb, pressed && styles.pressed]}
						>
							<Text
								numberOfLines={1}
								style={[
									styles.label,
									{ color: current ? colors.textMuted : colors.accent },
								]}
							>
								{crumb.name}
							</Text>
						</Pressable>
						{!current && (
							<Ionicons
								name="chevron-forward"
								size={14}
								color={colors.textMuted}
							/>
						)}
					</View>
				);
			})}
		</ScrollView>
	);
}

const styles = StyleSheet.create({
	fill: { flexGrow: 0 },
	content: { flexDirection: "row", alignItems: "center" },
	crumbGroup: { flexDirection: "row", alignItems: "center", gap: 4 },
	crumb: { minHeight: 44, justifyContent: "center" },
	label: { fontSize: 13, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

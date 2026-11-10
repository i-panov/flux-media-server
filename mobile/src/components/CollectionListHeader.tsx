import type { Collection } from "@flux/shared";
import { router } from "expo-router";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { collectionChildren } from "../collections/tree";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { CollectionTreeRow } from "./CollectionTreeRow";
import { InlineError } from "./InlineError";

interface CollectionListHeaderProps {
	collections: readonly Collection[];
	subcollections: readonly Collection[];
	selecting: boolean;
	itemsError: boolean;
	hasItems: boolean;
	onSelectPress: () => void;
	onRetryItems: () => void;
}

// Шапка списка элементов: вложенные коллекции, ошибка фонового рефетча
// и заголовок «Элементы» с кнопкой выбора.
export function CollectionListHeader({
	collections,
	subcollections,
	selecting,
	itemsError,
	hasItems,
	onSelectPress,
	onRetryItems,
}: CollectionListHeaderProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const selectLabel = selecting
		? t("collections.clearSelection")
		: t("collections.select");

	return (
		<View style={{ gap: spacing.sm }}>
			{subcollections.length > 0 && (
				<View style={{ gap: spacing.xs }} testID="collection-children">
					<Text style={[styles.sectionTitle, { color: colors.text }]}>
						{t("collections.children")}
					</Text>
					{subcollections.map((child) => (
						<CollectionTreeRow
							key={child.id}
							collection={child}
							depth={0}
							hasChildren={collectionChildren(collections, child.id).length > 0}
							expanded={false}
							onPress={() => router.push(`/collections/${child.id}`)}
							testIDPrefix="collection-child"
						/>
					))}
				</View>
			)}
			{itemsError && (
				<InlineError
					message={t("collections.itemsError")}
					onRetry={onRetryItems}
					testID="collection-items-inline-error"
				/>
			)}
			<View style={[styles.itemsHeader, { gap: spacing.sm }]}>
				<Text style={[styles.sectionTitle, { color: colors.text }]}>
					{t("collections.itemsSection")}
				</Text>
				{hasItems && (
					<Pressable
						accessibilityRole="button"
						accessibilityLabel={selectLabel}
						onPress={onSelectPress}
						testID={
							selecting ? "collection-select-cancel" : "collection-select"
						}
						hitSlop={4}
						style={({ pressed }) => [
							styles.selectButton,
							{ borderColor: colors.accent, borderRadius: radii.pill },
							pressed && styles.pressed,
						]}
					>
						<Text style={[styles.selectLabel, { color: colors.accent }]}>
							{selectLabel}
						</Text>
					</Pressable>
				)}
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	sectionTitle: { fontSize: 16, fontWeight: "700" },
	itemsHeader: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
	},
	selectButton: {
		minHeight: 44,
		justifyContent: "center",
		paddingHorizontal: 12,
		borderWidth: 1,
	},
	selectLabel: { fontSize: 13, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

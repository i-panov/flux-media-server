import Ionicons from "@expo/vector-icons/Ionicons";
import type { Collection } from "@flux/shared";
import { FlatList, Pressable, StyleSheet, Text, View } from "react-native";
import { useCollectionStats } from "../api/collections";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { isRowVisible } from "./homeRows";
import { SectionHeader } from "./SectionHeader";

const CARD_WIDTH = 148;

function typeLabel(type: string): string {
	return type === "audio"
		? t("collections.typeAudio")
		: t("collections.typeVideo");
}

function CollectionCard({
	collection,
	onPress,
}: {
	collection: Collection;
	onPress: () => void;
}) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const stats = useCollectionStats(collection.id);
	const count = stats.data?.items;
	const subtitle =
		count === undefined
			? typeLabel(collection.type)
			: `${typeLabel(collection.type)} · ${t("collections.itemCountNested", {
					count,
				})}`;

	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={`${collection.name}, ${subtitle}`}
			onPress={onPress}
			testID={`collection-card-${collection.id}`}
			style={({ pressed }) => [
				styles.card,
				{
					width: CARD_WIDTH,
					backgroundColor: colors.surface,
					borderColor: colors.borderStrong,
					borderRadius: radii.md,
					gap: spacing.xs,
					marginRight: spacing.sm,
					padding: spacing.md,
				},
				pressed && styles.pressed,
			]}
		>
			<Ionicons name="folder" size={28} color={colors.accent} />
			<Text numberOfLines={2} style={[styles.name, { color: colors.text }]}>
				{collection.name}
			</Text>
			<Text
				numberOfLines={1}
				style={[styles.meta, { color: colors.textMuted }]}
			>
				{subtitle}
			</Text>
		</Pressable>
	);
}

interface CollectionRowProps {
	collections: readonly Collection[];
	testID: string;
	onPressCollection: (collection: Collection) => void;
}

// Ряд коллекций выбранного типа: только корневые папки, без дублей
// вложенных. Пустой ряд скрыт до Task 17, который добавит создание.
export function CollectionRow({
	collections,
	testID,
	onPressCollection,
}: CollectionRowProps) {
	const { spacing } = useTheme();
	if (!isRowVisible(collections)) {
		return null;
	}
	return (
		<View style={{ gap: spacing.sm }} testID={testID}>
			<SectionHeader title={t("collections.title")} titleStyle={styles.title} />
			<FlatList
				horizontal
				showsHorizontalScrollIndicator={false}
				data={collections}
				keyExtractor={(collection) => String(collection.id)}
				accessibilityRole="list"
				renderItem={({ item }) => (
					<CollectionCard
						collection={item}
						onPress={() => onPressCollection(item)}
					/>
				)}
			/>
		</View>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 16, fontWeight: "700" },
	card: { borderWidth: 1, minHeight: 112 },
	name: { fontSize: 14, fontWeight: "600" },
	meta: { fontSize: 12 },
	pressed: { opacity: 0.7 },
});

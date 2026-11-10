import Ionicons from "@expo/vector-icons/Ionicons";
import type { Collection } from "@flux/shared";
import { Pressable, ScrollView, StyleSheet, Text } from "react-native";
import { flattenCollectionTree } from "../collections/tree";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface CollectionPickListProps {
	collections: readonly Collection[];
	type: string;
	excludeIds: ReadonlySet<number>;
	allowRoot: boolean;
	loading?: boolean;
	pending: boolean;
	onPick: (collectionId: number | null) => void;
}

// Общий список выбора родителя/цели: тот же тип, без исключённых
// (себя и потомков — иначе переезд замкнёт цикл). Дерево развёрнуто
// целиком, чтобы вложенные цели были видны с отступом.
export function CollectionPickList({
	collections,
	type,
	excludeIds,
	allowRoot,
	loading = false,
	pending,
	onPick,
}: CollectionPickListProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const nodes = flattenCollectionTree(collections, type, new Set()).filter(
		(node) => !excludeIds.has(node.collection.id),
	);

	if (loading) {
		return (
			<Text style={[styles.message, { color: colors.textMuted }]}>
				{t("common.loading")}
			</Text>
		);
	}

	if (!allowRoot && nodes.length === 0) {
		return (
			<Text style={[styles.message, { color: colors.textMuted }]}>
				{t("collections.emptyForMove")}
			</Text>
		);
	}

	return (
		<ScrollView
			style={styles.list}
			contentContainerStyle={{ gap: spacing.xs }}
			testID="collection-pick-list"
		>
			{allowRoot && (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("collections.moveToRoot")}
					disabled={pending}
					onPress={() => onPick(null)}
					testID="collection-pick-root"
					style={({ pressed }) => [
						styles.row,
						{
							backgroundColor: colors.surfaceMuted,
							borderRadius: radii.sm,
							paddingHorizontal: spacing.md,
						},
						(pressed || pending) && styles.pressed,
					]}
				>
					<Ionicons
						name="arrow-up-circle-outline"
						size={18}
						color={colors.text}
					/>
					<Text style={[styles.name, { color: colors.text }]}>
						{t("collections.moveToRoot")}
					</Text>
				</Pressable>
			)}
			{nodes.map(({ collection, depth }) => (
				<Pressable
					key={collection.id}
					accessibilityRole="button"
					accessibilityLabel={collection.name}
					disabled={pending}
					onPress={() => onPick(collection.id)}
					testID={`collection-pick-${collection.id}`}
					style={({ pressed }) => [
						styles.row,
						{
							backgroundColor: colors.surfaceMuted,
							borderRadius: radii.sm,
							paddingHorizontal: spacing.md,
							paddingLeft: spacing.md + depth * spacing.lg,
						},
						(pressed || pending) && styles.pressed,
					]}
				>
					<Ionicons name="folder-outline" size={18} color={colors.text} />
					<Text numberOfLines={1} style={[styles.name, { color: colors.text }]}>
						{collection.name}
					</Text>
				</Pressable>
			))}
		</ScrollView>
	);
}

const styles = StyleSheet.create({
	list: { maxHeight: 320 },
	message: { fontSize: 14, lineHeight: 20 },
	row: {
		flexDirection: "row",
		alignItems: "center",
		minHeight: 44,
		gap: 10,
	},
	name: { flex: 1, fontSize: 15, fontWeight: "600" },
	pressed: { opacity: 0.7 },
});

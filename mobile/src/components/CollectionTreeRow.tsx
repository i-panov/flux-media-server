import Ionicons from "@expo/vector-icons/Ionicons";
import type { Collection } from "@flux/shared";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { useCollectionStats } from "../api/collections";
import { collectionTypeLabel } from "../collections/labels";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";

interface CollectionTreeRowProps {
	collection: Collection;
	depth: number;
	hasChildren: boolean;
	expanded: boolean;
	onToggle?: () => void;
	onPress: () => void;
	testIDPrefix?: string;
}

// Узел дерева коллекций: отступ по глубине, шеврон только у родителей.
// Stats не запрашиваем на каждый узел при монтировании (N+1): берём только
// уже закэшированное значение, если оно есть после открытия delete-модалки.
export function CollectionTreeRow({
	collection,
	depth,
	hasChildren,
	expanded,
	onToggle,
	onPress,
	testIDPrefix = "collection-tree",
}: CollectionTreeRowProps) {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const stats = useCollectionStats(collection.id, false);
	const count = stats.data?.items;
	const typeLabel = collectionTypeLabel(collection.type);
	const subtitle =
		count === undefined
			? typeLabel
			: `${typeLabel} · ${t("collections.itemCountNested", { count })}`;
	const nested = (collection.parent_id ?? null) !== null;
	const accessibilityLabel = nested
		? `${collection.name}, ${subtitle}, ${t("collections.nested")}`
		: `${collection.name}, ${subtitle}`;

	return (
		<View
			style={[
				styles.row,
				{
					marginLeft: depth * spacing.lg,
					borderColor: colors.border,
					backgroundColor: colors.surface,
					borderRadius: radii.md,
					gap: spacing.xs,
					paddingRight: spacing.sm,
				},
			]}
		>
			{hasChildren && onToggle !== undefined ? (
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={
						expanded ? t("collections.collapse") : t("collections.expand")
					}
					accessibilityState={{ expanded }}
					onPress={onToggle}
					testID={`${testIDPrefix}-toggle-${collection.id}`}
					hitSlop={4}
					style={({ pressed }) => [styles.toggle, pressed && styles.pressed]}
				>
					<Ionicons
						name={expanded ? "chevron-down" : "chevron-forward"}
						size={18}
						color={colors.textMuted}
					/>
				</Pressable>
			) : (
				<View style={styles.toggle}>
					{hasChildren && (
						<Ionicons
							name="chevron-forward"
							size={18}
							color={colors.textMuted}
						/>
					)}
				</View>
			)}
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={accessibilityLabel}
				onPress={onPress}
				testID={`${testIDPrefix}-${collection.id}`}
				style={({ pressed }) => [styles.body, pressed && styles.pressed]}
			>
				<View
					style={[styles.iconCircle, { backgroundColor: colors.surfaceMuted }]}
				>
					<Ionicons
						name={hasChildren ? "folder" : "folder-outline"}
						size={18}
						color={colors.accent}
					/>
				</View>
				<View style={styles.info}>
					<Text numberOfLines={1} style={[styles.name, { color: colors.text }]}>
						{collection.name}
					</Text>
					<Text
						numberOfLines={1}
						style={[styles.meta, { color: colors.textMuted }]}
					>
						{subtitle}
					</Text>
				</View>
				<Ionicons name="chevron-forward" size={18} color={colors.textMuted} />
			</Pressable>
		</View>
	);
}

const styles = StyleSheet.create({
	row: {
		flexDirection: "row",
		alignItems: "center",
		borderWidth: 1,
		minHeight: 56,
	},
	toggle: {
		width: 44,
		height: 44,
		alignItems: "center",
		justifyContent: "center",
	},
	body: {
		flex: 1,
		flexDirection: "row",
		alignItems: "center",
		gap: 10,
		minHeight: 44,
		paddingVertical: 6,
	},
	iconCircle: {
		width: 32,
		height: 32,
		borderRadius: 16,
		alignItems: "center",
		justifyContent: "center",
	},
	info: { flex: 1 },
	name: { fontSize: 15, fontWeight: "600" },
	meta: { fontSize: 12 },
	pressed: { opacity: 0.7 },
});

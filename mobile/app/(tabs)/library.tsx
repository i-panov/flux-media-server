import Ionicons from "@expo/vector-icons/Ionicons";
import { router } from "expo-router";
import { useState } from "react";
import {
	ActivityIndicator,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useCollections } from "../../src/api/collections";
import { useSession } from "../../src/auth/session";
import {
	collectionChildren,
	flattenCollectionTree,
} from "../../src/collections/tree";
import { CollectionTreeRow } from "../../src/components/CollectionTreeRow";
import { CreateCollectionModal } from "../../src/components/CreateCollectionModal";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import { InlineError } from "../../src/components/InlineError";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

function toggleCollapsed(
	collapsed: ReadonlySet<number>,
	collectionId: number,
): Set<number> {
	const next = new Set(collapsed);
	if (next.has(collectionId)) {
		next.delete(collectionId);
	} else {
		next.add(collectionId);
	}
	return next;
}

function LibraryUploadRow() {
	const { colors, spacing } = useTheme();
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={t("upload.title")}
			onPress={() => router.push("/upload")}
			testID="library-upload"
			style={({ pressed }) => [
				styles.row,
				{
					padding: spacing.lg,
					borderColor: colors.border,
					backgroundColor: colors.surface,
				},
				pressed && styles.pressed,
			]}
		>
			<View style={styles.rowLead}>
				<Ionicons
					name="cloud-upload-outline"
					size={20}
					color={colors.textMuted}
				/>
				<Text style={[styles.rowTitle, { color: colors.text }]}>
					{t("upload.title")}
				</Text>
			</View>
			<Ionicons name="chevron-forward" size={18} color={colors.textMuted} />
		</Pressable>
	);
}

export default function LibraryScreen() {
	useLanguage();
	const { colors, radii, spacing } = useTheme();
	const collections = useCollections();
	const session = useSession();
	const isAdmin = session.data?.is_admin === true;
	const [collapsed, setCollapsed] = useState<Set<number>>(new Set());
	const [createOpen, setCreateOpen] = useState(false);
	const all = collections.data ?? [];
	const nodes = flattenCollectionTree(all, undefined, collapsed);
	const hasCachedData = collections.data !== undefined;

	const openCreate = () => setCreateOpen(true);

	return (
		<Screen scroll testID="library-screen">
			<Text style={[styles.title, { color: colors.text }]}>
				{t("library.title")}
			</Text>
			<Text style={[styles.hint, { color: colors.textMuted }]}>
				{t("library.hint")}
			</Text>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("artists.title")}
				onPress={() => router.push("/artists")}
				testID="library-artists"
				style={({ pressed }) => [
					styles.row,
					{
						padding: spacing.lg,
						borderColor: colors.border,
						backgroundColor: colors.surface,
					},
					pressed && styles.pressed,
				]}
			>
				<View style={styles.rowLead}>
					<Ionicons name="people-outline" size={20} color={colors.textMuted} />
					<Text style={[styles.rowTitle, { color: colors.text }]}>
						{t("artists.title")}
					</Text>
				</View>
				<Ionicons name="chevron-forward" size={18} color={colors.textMuted} />
			</Pressable>

			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("trash.title")}
				onPress={() => router.push("/trash")}
				testID="library-trash"
				style={({ pressed }) => [
					styles.row,
					{
						padding: spacing.lg,
						borderColor: colors.border,
						backgroundColor: colors.surface,
					},
					pressed && styles.pressed,
				]}
			>
				<View style={styles.rowLead}>
					<Ionicons name="trash-outline" size={20} color={colors.textMuted} />
					<Text style={[styles.rowTitle, { color: colors.text }]}>
						{t("trash.title")}
					</Text>
				</View>
				<Ionicons name="chevron-forward" size={18} color={colors.textMuted} />
			</Pressable>

			{isAdmin && <LibraryUploadRow />}

			<View style={[styles.sectionHeader, { gap: spacing.sm }]}>
				<Text style={[styles.sectionTitle, { color: colors.text }]}>
					{t("collections.title")}
				</Text>
				<Pressable
					accessibilityRole="button"
					accessibilityLabel={t("collections.create")}
					onPress={openCreate}
					testID="library-create-collection"
					hitSlop={4}
					style={({ pressed }) => [
						styles.createButton,
						{
							borderColor: colors.accent,
							backgroundColor: colors.surface,
							borderRadius: radii.pill,
							gap: spacing.xs,
							paddingHorizontal: spacing.md,
						},
						pressed && styles.pressed,
					]}
				>
					<Ionicons name="add" size={18} color={colors.accent} />
					<Text style={[styles.createLabel, { color: colors.accent }]}>
						{t("common.create")}
					</Text>
				</Pressable>
			</View>

			{collections.isError && hasCachedData && (
				<InlineError
					message={t("collections.loadError")}
					onRetry={() => void collections.refetch()}
					testID="library-collections-inline-error"
				/>
			)}

			{collections.isPending ? (
				<View
					style={[styles.center, { gap: spacing.sm }]}
					testID="library-collections-loading"
				>
					<ActivityIndicator color={colors.accent} />
					<Text style={{ color: colors.textMuted }}>{t("common.loading")}</Text>
				</View>
			) : collections.isError && !hasCachedData ? (
				<ErrorState
					title={t("collections.loadError")}
					onRetry={() => void collections.refetch()}
					testID="library-collections-error"
				/>
			) : nodes.length === 0 ? (
				<EmptyState
					icon="folder-open-outline"
					title={t("collections.empty")}
					description={t("collections.emptyHint")}
					actionLabel={t("collections.create")}
					onActionPress={openCreate}
					testID="library-collections-empty"
				/>
			) : (
				<View
					style={{ gap: spacing.xs }}
					testID="library-collections"
					accessibilityRole="list"
				>
					{nodes.map((node) => {
						const hasChildren =
							collectionChildren(all, node.collection.id).length > 0;
						return (
							<CollectionTreeRow
								key={node.collection.id}
								collection={node.collection}
								depth={node.depth}
								hasChildren={hasChildren}
								expanded={!collapsed.has(node.collection.id)}
								onToggle={() =>
									setCollapsed((previous) =>
										toggleCollapsed(previous, node.collection.id),
									)
								}
								onPress={() =>
									router.push(`/collections/${node.collection.id}`)
								}
							/>
						);
					})}
				</View>
			)}

			<Pressable
				disabled
				accessibilityRole="button"
				accessibilityState={{ disabled: true }}
				testID="library-favorites"
				style={[
					styles.row,
					{
						padding: spacing.lg,
						borderColor: colors.border,
						backgroundColor: colors.surface,
					},
				]}
			>
				<View style={styles.rowLead}>
					<Ionicons name="heart-outline" size={20} color={colors.textMuted} />
					<Text style={[styles.rowTitle, { color: colors.text }]}>
						{t("library.favorites")}
					</Text>
				</View>
				<Text style={[styles.soon, { color: colors.textMuted }]}>
					{t("library.soon")}
				</Text>
			</Pressable>

			{createOpen && (
				<CreateCollectionModal
					visible
					onClose={() => setCreateOpen(false)}
					defaultType="video"
				/>
			)}
		</Screen>
	);
}

const styles = StyleSheet.create({
	title: { fontSize: 24, fontWeight: "700" },
	hint: { fontSize: 14 },
	row: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		borderWidth: 1,
		borderRadius: 10,
	},
	rowLead: { flexDirection: "row", alignItems: "center", gap: 10 },
	rowTitle: { fontSize: 16, fontWeight: "600" },
	soon: { fontSize: 12 },
	sectionHeader: {
		flexDirection: "row",
		alignItems: "center",
		justifyContent: "space-between",
		marginTop: 4,
	},
	sectionTitle: { fontSize: 18, fontWeight: "700" },
	createButton: {
		flexDirection: "row",
		alignItems: "center",
		minHeight: 44,
		borderWidth: 1,
	},
	createLabel: { fontSize: 14, fontWeight: "600" },
	center: { alignItems: "center", justifyContent: "center", padding: 24 },
	pressed: { opacity: 0.7 },
});

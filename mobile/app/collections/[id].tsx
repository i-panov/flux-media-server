import { router, useLocalSearchParams } from "expo-router";
import { useMemo, useState } from "react";
import {
	ActivityIndicator,
	FlatList,
	RefreshControl,
	StyleSheet,
	Text,
	View,
} from "react-native";
import {
	isCollectionMissing,
	useCollectionItems,
	useCollections,
} from "../../src/api/collections";
import type { CollectionDialog } from "../../src/collections/dialog";
import { collectionTypeLabel } from "../../src/collections/labels";
import {
	asMediaType,
	collectionBreadcrumbs,
	collectionChildren,
} from "../../src/collections/tree";
import { useCollectionItemActions } from "../../src/collections/useCollectionItemActions";
import { useCollectionSelection } from "../../src/collections/useCollectionSelection";
import { AuthGate } from "../../src/components/AuthGate";
import { CollectionActionBar } from "../../src/components/CollectionActionBar";
import { CollectionBackHeader } from "../../src/components/CollectionBackHeader";
import { CollectionBreadcrumbs } from "../../src/components/CollectionBreadcrumbs";
import { CollectionBulkBar } from "../../src/components/CollectionBulkBar";
import { CollectionDialogs } from "../../src/components/CollectionDialogs";
import { CollectionItemRow } from "../../src/components/CollectionItemRow";
import { CollectionListHeader } from "../../src/components/CollectionListHeader";
import { CollectionScreenState } from "../../src/components/CollectionScreenState";
import { EmptyState } from "../../src/components/EmptyState";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

const COLLECTION_ID_PATTERN = /^\d+$/;

function parseCollectionId(
	value: string | readonly string[] | undefined,
): number | null {
	const raw = Array.isArray(value) ? value[0] : value;
	if (raw === undefined || !COLLECTION_ID_PATTERN.test(raw)) {
		return null;
	}
	const id = Number(raw);
	return Number.isSafeInteger(id) && id > 0 ? id : null;
}

function closeCollection(type: string | undefined): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace(type === "audio" ? "/audio" : "/video");
}

function CollectionContent({ collectionId }: { collectionId: number | null }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const valid = collectionId !== null;
	const collections = useCollections();
	const items = useCollectionItems(collectionId ?? 0, valid);
	const media = useMemo(() => items.data ?? [], [items.data]);
	const availableIds = useMemo(
		() => new Set(media.map((item) => item.id)),
		[media],
	);
	const selection = useCollectionSelection(availableIds);
	const [dialog, setDialog] = useState<CollectionDialog>(null);

	const all = collections.data ?? [];
	const collection =
		collectionId === null
			? undefined
			: all.find((entry) => entry.id === collectionId);
	const actions = useCollectionItemActions({
		collectionId: collection?.id ?? null,
		media,
		selection,
		setDialog,
	});

	if (!valid) {
		return (
			<CollectionScreenState
				kind="notFound"
				onBack={() => closeCollection(undefined)}
			/>
		);
	}

	if (collections.isError && collections.data === undefined) {
		return (
			<CollectionScreenState
				kind="loadError"
				onBack={() => closeCollection(undefined)}
				onRetry={() => void collections.refetch()}
			/>
		);
	}

	if (collections.isPending) {
		return (
			<CollectionScreenState
				kind="loading"
				onBack={() => closeCollection(undefined)}
			/>
		);
	}

	if (collection === undefined) {
		return (
			<CollectionScreenState
				kind="notFound"
				onBack={() => closeCollection(undefined)}
			/>
		);
	}

	const missing = isCollectionMissing(items.error);
	if (missing || (items.isError && items.data === undefined)) {
		return (
			<CollectionScreenState
				kind={missing ? "notFound" : "itemsError"}
				title={collection.name}
				onBack={() => closeCollection(collection.type)}
				onRetry={missing ? undefined : () => void items.refetch()}
			/>
		);
	}

	const children = collectionChildren(all, collection.id);
	const crumbs = collectionBreadcrumbs(all, collection.id);
	const addableType = asMediaType(collection.type);
	const canAddSubcollection = addableType !== null && addableType !== "image";
	const typeLabel = collectionTypeLabel(collection.type);
	const count = items.data?.length;
	const subtitle =
		count === undefined
			? typeLabel
			: `${typeLabel} · ${t("collections.itemCount", { count })}`;

	return (
		<Screen testID="collection-screen" edges={["top", "bottom"]}>
			<CollectionBackHeader
				title={collection.name}
				subtitle={subtitle}
				onBack={() => closeCollection(collection.type)}
			/>
			<CollectionBreadcrumbs
				crumbs={crumbs}
				onPress={(id) => router.push(`/collections/${id}`)}
			/>
			<CollectionActionBar
				canAddSubcollection={canAddSubcollection}
				onAddSubcollection={() => setDialog({ kind: "create" })}
				onRename={() => setDialog({ kind: "rename" })}
				onMove={() => setDialog({ kind: "move" })}
				onDelete={() => setDialog({ kind: "delete" })}
			/>
			<FlatList
				testID="collection-items"
				data={media}
				keyExtractor={(item) => String(item.id)}
				style={styles.fill}
				contentContainerStyle={
					media.length === 0 ? styles.emptyList : styles.list
				}
				ListHeaderComponent={
					<CollectionListHeader
						collections={all}
						subcollections={children}
						selecting={selection.selecting}
						itemsError={items.isError && items.data !== undefined}
						hasItems={media.length > 0}
						onSelectPress={() => {
							if (selection.selecting) {
								selection.exit();
								return;
							}
							selection.begin();
						}}
						onRetryItems={() => void items.refetch()}
					/>
				}
				ListEmptyComponent={
					items.isPending ? (
						<View style={[styles.center, { gap: spacing.sm }]}>
							<ActivityIndicator color={colors.accent} />
							<Text style={{ color: colors.textMuted }}>
								{t("common.loading")}
							</Text>
						</View>
					) : (
						<EmptyState
							icon="folder-open-outline"
							title={t("collections.emptyItems")}
							testID="collection-items-empty"
						/>
					)
				}
				refreshControl={
					<RefreshControl
						refreshing={collections.isRefetching || items.isRefetching}
						onRefresh={() => {
							void collections.refetch();
							void items.refetch();
						}}
						tintColor={colors.accent}
					/>
				}
				renderItem={({ item }) => (
					<CollectionItemRow
						item={item}
						selecting={selection.selecting}
						selected={selection.selected.has(item.id)}
						onPress={() => actions.onItemPress(item)}
						onLongPress={() => selection.start(item.id)}
						onMove={() => actions.moveOne(item.id)}
						onRemove={() => actions.removeOne(item)}
					/>
				)}
			/>
			{selection.selecting && (
				<CollectionBulkBar
					count={selection.selected.size}
					busy={actions.bulkPending || selection.selected.size === 0}
					onMove={() => {
						if (selection.selected.size > 0) {
							setDialog({
								kind: "moveItems",
								mediaIds: [...selection.selected],
							});
						}
					}}
					onRemove={actions.confirmBulkRemove}
					onClear={selection.exit}
				/>
			)}
			<CollectionDialogs
				dialog={dialog}
				collection={collection}
				collections={all}
				onClose={() => setDialog(null)}
				onMoved={actions.handleMoved}
				onDeleted={() => closeCollection(collection.type)}
			/>
		</Screen>
	);
}

export default function CollectionScreen() {
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const collectionId = parseCollectionId(params.id);
	return (
		<AuthGate>
			<CollectionContent
				key={collectionId ?? "invalid"}
				collectionId={collectionId}
			/>
		</AuthGate>
	);
}

const styles = StyleSheet.create({
	fill: { flex: 1 },
	list: { gap: 8, paddingBottom: 24 },
	emptyList: { flexGrow: 1, gap: 8 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
});

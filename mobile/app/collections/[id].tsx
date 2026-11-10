import Ionicons from "@expo/vector-icons/Ionicons";
import { formatDuration, type Media } from "@flux/shared";
import { router, useLocalSearchParams } from "expo-router";
import {
	ActivityIndicator,
	FlatList,
	Pressable,
	StyleSheet,
	Text,
	View,
} from "react-native";
import { useCollectionItems, useCollections } from "../../src/api/collections";
import { AuthGate } from "../../src/components/AuthGate";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useAudioActions } from "../../src/player/AudioProvider";
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

function typeLabel(type: string): string {
	return type === "audio"
		? t("collections.typeAudio")
		: t("collections.typeVideo");
}

function closeCollection(type: string | undefined): void {
	if (router.canGoBack()) {
		router.back();
		return;
	}
	router.replace(type === "audio" ? "/audio" : "/video");
}

function Header({ title, type }: { title: string; type?: string }) {
	const { colors, spacing } = useTheme();
	return (
		<View style={[styles.header, { gap: spacing.sm }]}>
			<Pressable
				accessibilityRole="button"
				accessibilityLabel={t("common.back")}
				onPress={() => closeCollection(type)}
				testID="collection-detail-back"
				hitSlop={8}
				style={({ pressed }) => [
					styles.headerButton,
					pressed && styles.pressed,
				]}
			>
				<Ionicons name="chevron-back" size={24} color={colors.text} />
			</Pressable>
			<Text
				numberOfLines={1}
				style={[styles.headerTitle, { color: colors.text }]}
			>
				{title}
			</Text>
			<View style={styles.headerButton} />
		</View>
	);
}

function CollectionItemRow({
	item,
	onPress,
}: {
	item: Media;
	onPress: () => void;
}) {
	const { colors, spacing } = useTheme();
	const artists = item.artists.map((artist) => artist.name).join(", ");
	return (
		<Pressable
			accessibilityRole="button"
			accessibilityLabel={item.title}
			onPress={onPress}
			testID={`collection-item-${item.id}`}
			style={({ pressed }) => [
				styles.row,
				{
					gap: spacing.md,
					padding: spacing.md,
					borderColor: colors.border,
					backgroundColor: colors.surface,
				},
				pressed && styles.pressed,
			]}
		>
			<View style={styles.rowInfo}>
				<Text
					numberOfLines={2}
					style={[styles.rowTitle, { color: colors.text }]}
				>
					{item.title}
				</Text>
				{artists !== "" && (
					<Text
						numberOfLines={1}
						style={[styles.rowMeta, { color: colors.textMuted }]}
					>
						{artists}
					</Text>
				)}
			</View>
			<Text style={[styles.rowMeta, { color: colors.textMuted }]}>
				{formatDuration(item.duration)}
			</Text>
		</Pressable>
	);
}

function CollectionContent({ collectionId }: { collectionId: number | null }) {
	useLanguage();
	const { colors } = useTheme();
	const valid = collectionId !== null;
	const collections = useCollections();
	const items = useCollectionItems(collectionId ?? 0, valid);
	const { playQueue } = useAudioActions();
	const collection = (collections.data ?? []).find(
		(entry) => entry.id === collectionId,
	);
	const type = collection?.type;

	const header = (
		<Header
			title={collection?.name ?? t("collections.detailTitle")}
			type={type}
		/>
	);

	if (!valid || (collections.isError && collections.data === undefined)) {
		return (
			<Screen edges={["top", "bottom"]}>
				{header}
				{valid ? (
					<ErrorState
						title={t("collections.loadError")}
						onRetry={() => void collections.refetch()}
						testID="collection-detail-error"
					/>
				) : (
					<EmptyState
						icon="folder-open-outline"
						title={t("collections.notFound")}
						description={t("collections.notFoundHint")}
						testID="collection-detail-not-found"
					/>
				)}
			</Screen>
		);
	}

	if (collections.isPending) {
		return (
			<Screen edges={["top", "bottom"]}>
				{header}
				<View style={styles.center}>
					<ActivityIndicator color={colors.accent} />
				</View>
			</Screen>
		);
	}

	if (collection === undefined) {
		return (
			<Screen edges={["top", "bottom"]}>
				{header}
				<EmptyState
					icon="folder-open-outline"
					title={t("collections.notFound")}
					description={t("collections.notFoundHint")}
					testID="collection-detail-not-found"
				/>
			</Screen>
		);
	}

	// Счётчик прямой, без вложенных: он должен совпадать с элементами,
	// которые реально перечислены на этом экране. Stats ряда показывает
	// поддерево и помечен отдельным текстом.
	const count = items.data?.length;
	const subtitle =
		count === undefined
			? typeLabel(collection.type)
			: `${typeLabel(collection.type)} · ${t("collections.itemCount", { count })}`;

	const play = (item: Media) => {
		if (item.type !== "audio") {
			router.push(`/video/${item.id}`);
			return;
		}
		const queue = items.data ?? [item];
		const index = queue.findIndex((entry) => entry.id === item.id);
		playQueue(queue, Math.max(index, 0));
		router.push("/player");
	};

	if (items.isPending) {
		return (
			<Screen edges={["top", "bottom"]}>
				{header}
				<Text style={{ color: colors.textMuted }}>{subtitle}</Text>
				<View style={styles.center}>
					<ActivityIndicator color={colors.accent} />
				</View>
			</Screen>
		);
	}

	if (items.isError && items.data === undefined) {
		return (
			<Screen edges={["top", "bottom"]}>
				{header}
				<ErrorState
					title={t("collections.itemsError")}
					onRetry={() => void items.refetch()}
					testID="collection-items-error"
				/>
			</Screen>
		);
	}

	const media = items.data ?? [];
	return (
		<Screen testID="collection-screen" edges={["top", "bottom"]}>
			{header}
			<Text style={[styles.subtitle, { color: colors.textMuted }]}>
				{subtitle}
			</Text>
			<FlatList
				testID="collection-items"
				data={media}
				keyExtractor={(item) => String(item.id)}
				style={styles.fill}
				contentContainerStyle={styles.list}
				ListEmptyComponent={
					<EmptyState
						icon="folder-open-outline"
						title={t("collections.emptyItems")}
						testID="collection-items-empty"
					/>
				}
				renderItem={({ item }) => (
					<CollectionItemRow item={item} onPress={() => play(item)} />
				)}
			/>
		</Screen>
	);
}

// Минимальный экран Task 16: заголовок, тип, счётчик и элементы. Полные
// CRUD/bulk-операции и дерево появятся в Task 17, но маршрут уже рабочий.
export default function CollectionScreen() {
	const params = useLocalSearchParams<{ id?: string | string[] }>();
	const collectionId = parseCollectionId(params.id);
	return (
		<AuthGate>
			<CollectionContent collectionId={collectionId} />
		</AuthGate>
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
	headerTitle: { flex: 1, fontSize: 18, fontWeight: "700" },
	subtitle: { fontSize: 13 },
	fill: { flex: 1 },
	list: { gap: 8, paddingBottom: 24 },
	center: { flex: 1, alignItems: "center", justifyContent: "center" },
	row: {
		flexDirection: "row",
		alignItems: "center",
		borderWidth: 1,
		borderRadius: 10,
	},
	rowInfo: { flex: 1 },
	rowTitle: { fontSize: 16, fontWeight: "600" },
	rowMeta: { fontSize: 13 },
	pressed: { opacity: 0.7 },
});

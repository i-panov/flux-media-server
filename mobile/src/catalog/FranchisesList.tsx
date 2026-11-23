import { router } from "expo-router";
import { ActivityIndicator, FlatList, useWindowDimensions } from "react-native";
import { useFranchises } from "../api/catalog";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { isTV } from "../tv/profile";
import { CatalogCard } from "./CatalogCard";
import { catalogCardWidth, catalogColumns, catalogPadding } from "./grid";

export function FranchisesList({ tagIDs = [] }: { tagIDs?: number[] }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const franchises = useFranchises(tagIDs);
	const { width } = useWindowDimensions();
	const columns = catalogColumns(width);
	// Отступы берём те же, что Screen: на TV они больше, иначе строка
	// шире контента и правая карточка обрезается.
	const padding = catalogPadding(isTV);
	const cardWidth = catalogCardWidth(width, columns, padding, spacing.md);
	if (franchises.isPending) {
		return <ActivityIndicator color={colors.accent} />;
	}
	if (franchises.isError) {
		return (
			<ErrorState
				title={t("catalog.loadError")}
				onRetry={() => void franchises.refetch()}
			/>
		);
	}
	if ((franchises.data ?? []).length === 0) {
		return (
			<EmptyState title={t("catalog.emptyFranchises")} icon="film-outline" />
		);
	}
	return (
		<FlatList
			key={`franchises-${columns}`}
			data={franchises.data ?? []}
			keyExtractor={(franchise) => String(franchise.id)}
			numColumns={columns}
			style={{ flex: 1 }}
			contentContainerStyle={{ gap: spacing.md, paddingBottom: spacing.lg }}
			columnWrapperStyle={{ gap: spacing.md }}
			renderItem={({ item: franchise }) => (
				<CatalogCard
					style={{ width: cardWidth }}
					id={franchise.id}
					title={franchise.name}
					coverURL={franchise.cover_url}
					icon="film"
					testID={`franchise-card-${franchise.id}`}
					onPress={() => router.push(`/franchises/${franchise.id}`)}
				/>
			)}
		/>
	);
}

import { router } from "expo-router";
import { ActivityIndicator, FlatList } from "react-native";
import { useFranchises } from "../api/catalog";
import { EmptyState } from "../components/EmptyState";
import { ErrorState } from "../components/ErrorState";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { CatalogCard } from "./CatalogCard";

export function FranchisesList() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const franchises = useFranchises();
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
			data={franchises.data ?? []}
			keyExtractor={(franchise) => String(franchise.id)}
			numColumns={2}
			style={{ flex: 1 }}
			contentContainerStyle={{ gap: spacing.md, paddingBottom: spacing.lg }}
			columnWrapperStyle={{ gap: spacing.md }}
			renderItem={({ item: franchise }) => (
				<CatalogCard
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

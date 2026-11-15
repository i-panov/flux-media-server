import { router } from "expo-router";
import { ActivityIndicator, View } from "react-native";
import { useFranchises } from "../../src/api/catalog";
import { CatalogCard } from "../../src/catalog/CatalogCard";
import { CatalogHeader } from "../../src/catalog/CatalogHeader";
import { CreateCatalogButton } from "../../src/catalog/CreateCatalogButton";
import { AuthGate } from "../../src/components/AuthGate";
import { EmptyState } from "../../src/components/EmptyState";
import { ErrorState } from "../../src/components/ErrorState";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function FranchisesScreen() {
	return (
		<AuthGate>
			<FranchisesContent />
		</AuthGate>
	);
}

function FranchisesContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const franchises = useFranchises();
	return (
		<Screen scroll>
			<CatalogHeader
				title={t("catalog.franchises")}
				onBack={() => router.replace("/video")}
			/>
			<CreateCatalogButton mode="franchise" />
			{franchises.isPending ? (
				<ActivityIndicator color={colors.accent} />
			) : franchises.isError ? (
				<ErrorState
					title={t("catalog.loadError")}
					onRetry={() => void franchises.refetch()}
				/>
			) : (franchises.data ?? []).length === 0 ? (
				<EmptyState title={t("catalog.emptyFranchises")} icon="film-outline" />
			) : (
				<View
					style={{ flexDirection: "row", flexWrap: "wrap", gap: spacing.md }}
				>
					{franchises.data?.map((franchise) => (
						<CatalogCard
							key={franchise.id}
							id={franchise.id}
							title={franchise.name}
							coverURL={franchise.cover_url}
							icon="film"
							testID={`franchise-card-${franchise.id}`}
							onPress={() => router.push(`/franchises/${franchise.id}`)}
						/>
					))}
				</View>
			)}
		</Screen>
	);
}

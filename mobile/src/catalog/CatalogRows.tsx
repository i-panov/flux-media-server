import { router } from "expo-router";
import { Pressable, ScrollView, Text, View } from "react-native";
import { useFranchises, useWorks } from "../api/catalog";
import { HOME_ROW_LIMIT } from "../components/homeRows";
import { SectionHeader } from "../components/SectionHeader";
import { t, useLanguage } from "../i18n";
import { useTheme } from "../theme/ThemeProvider";
import { CatalogCard } from "./CatalogCard";

export function CatalogRows({ hidden = false }: { hidden?: boolean }) {
	useLanguage();
	const { colors, spacing } = useTheme();
	const series = useWorks("series");
	const films = useWorks("film_series");
	const franchises = useFranchises();
	if (hidden) return null;
	const error = series.isError || films.isError || franchises.isError;
	const hasRows =
		(series.data?.length ?? 0) > 0 ||
		(films.data?.length ?? 0) > 0 ||
		(franchises.data?.length ?? 0) > 0;
	if (!hasRows && !error) return null;
	return (
		<View style={{ gap: spacing.lg, marginBottom: spacing.lg }}>
			<CatalogSection
				title={t("catalog.series")}
				works={(series.data ?? []).slice(0, HOME_ROW_LIMIT)}
				icon="tv"
				testID="catalog-series-row"
			/>
			<CatalogSection
				title={t("catalog.filmSeriesPlural")}
				works={(films.data ?? []).slice(0, HOME_ROW_LIMIT)}
				icon="film"
				testID="catalog-films-row"
			/>
			{franchises.data !== undefined && franchises.data.length > 0 && (
				<View style={{ gap: spacing.sm }} testID="catalog-franchises-row">
					<SectionHeader
						title={t("catalog.franchises")}
						actionLabel={t("catalog.all")}
						onActionPress={() => router.push("/franchises")}
						actionTestID="catalog-all-franchises"
					/>
					<ScrollView
						horizontal
						showsHorizontalScrollIndicator={false}
						contentContainerStyle={{ gap: spacing.sm }}
					>
						{franchises.data.slice(0, HOME_ROW_LIMIT).map((franchise) => (
							<CatalogCard
								key={franchise.id}
								id={franchise.id}
								title={franchise.name}
								coverURL={franchise.cover_url}
								icon="film"
								testID={`catalog-franchise-${franchise.id}`}
								onPress={() => router.push(`/franchises/${franchise.id}`)}
							/>
						))}
					</ScrollView>
				</View>
			)}
			{error && (
				<Pressable
					onPress={() => {
						void series.refetch();
						void films.refetch();
						void franchises.refetch();
					}}
				>
					<Text style={{ color: colors.danger }}>
						{t("catalog.loadError")} · {t("common.retry")}
					</Text>
				</Pressable>
			)}
		</View>
	);
}

function CatalogSection({
	title,
	works,
	icon,
	testID,
}: {
	title: string;
	works: readonly import("../api/catalog").CatalogWork[];
	icon: "tv" | "film";
	testID: string;
}) {
	const { spacing } = useTheme();
	if (works.length === 0) return null;
	return (
		<View style={{ gap: spacing.sm }} testID={testID}>
			<SectionHeader
				title={title}
				actionLabel={t("catalog.all")}
				onActionPress={() => router.push("/series")}
				actionTestID="catalog-all-series"
			/>
			<ScrollView
				horizontal
				showsHorizontalScrollIndicator={false}
				contentContainerStyle={{ gap: spacing.sm }}
			>
				{works.map((work) => (
					<CatalogCard
						key={work.id}
						id={work.id}
						title={work.title}
						coverURL={work.cover_url}
						icon={icon}
						testID={`catalog-work-${work.id}`}
						onPress={() => router.push(`/series/${work.id}`)}
					/>
				))}
			</ScrollView>
		</View>
	);
}

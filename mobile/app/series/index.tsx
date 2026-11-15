import { router } from "expo-router";
import { ActivityIndicator, Pressable, Text, View } from "react-native";
import { useWorks } from "../../src/api/catalog";
import { CatalogCard } from "../../src/catalog/CatalogCard";
import { CatalogHeader } from "../../src/catalog/CatalogHeader";
import { mergeWorks } from "../../src/catalog/catalogView";
import { AuthGate } from "../../src/components/AuthGate";
import { EmptyState } from "../../src/components/EmptyState";
import { Screen } from "../../src/components/Screen";
import { t, useLanguage } from "../../src/i18n";
import { useTheme } from "../../src/theme/ThemeProvider";

export default function SeriesScreen() {
	return (
		<AuthGate>
			<SeriesContent />
		</AuthGate>
	);
}

function SeriesContent() {
	useLanguage();
	const { colors, spacing } = useTheme();
	const series = useWorks("series");
	const films = useWorks("film_series");
	const works = mergeWorks(series.data, films.data);
	const loading = series.isPending && films.isPending;
	return (
		<Screen scroll>
			<CatalogHeader
				title={t("catalog.series")}
				onBack={() => router.replace("/video")}
			/>
			{loading ? (
				<ActivityIndicator color={colors.accent} />
			) : (
				<>
					{series.isError && (
						<Pressable onPress={() => void series.refetch()}>
							<Text style={{ color: colors.danger }}>
								{t("catalog.loadError")} · {t("common.retry")}
							</Text>
						</Pressable>
					)}
					{films.isError && (
						<Pressable onPress={() => void films.refetch()}>
							<Text style={{ color: colors.danger }}>
								{t("catalog.loadError")} · {t("common.retry")}
							</Text>
						</Pressable>
					)}
					{works.length === 0 && !series.isError && !films.isError ? (
						<EmptyState title={t("catalog.emptySeries")} icon="tv-outline" />
					) : (
						<View
							style={{
								flexDirection: "row",
								flexWrap: "wrap",
								gap: spacing.md,
							}}
						>
							{works.map((work) => (
								<CatalogCard
									key={work.id}
									id={work.id}
									title={work.title}
									coverURL={work.cover_url}
									icon={work.kind === "series" ? "tv" : "film"}
									testID={`series-card-${work.id}`}
									onPress={() => router.push(`/series/${work.id}`)}
								/>
							))}
						</View>
					)}
				</>
			)}
		</Screen>
	);
}
